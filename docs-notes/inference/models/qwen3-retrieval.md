# qwen3-retrieval: Qwen3-Embedding-8B + Qwen3-Reranker-4B

The retrieval models behind the AI gateway (C-349, 2026-11-01), used for agent
memory and doc search. The embedding model and its canonical dimension are a
one-time choice, recorded in agent-context
`docs/decisions/2026-11-01-embedding-model.md`. Changing either one means
re-embedding everything. The reranker is stateless and can be swapped freely.

- Deployment: `kubernetes/apps/inference/models/qwen3-retrieval/`
- Weights Job: `kubernetes/apps/inference/models/qwen3-retrieval/weights/`
- Gateway routes: `kubernetes/clusters/fairy-k8s01/apps/inference/ai-routes/route.yaml`

## How to call it

In-cluster, through `http://ai-gateway.inference.svc.cluster.local`. The model
CNP admits only the gateway.

| Use | Endpoint | `model` | Notes |
|---|---|---|---|
| Embeddings | `POST /v1/embeddings` (OpenAI) | `Qwen/Qwen3-Embedding-8B` | Always send `"dimensions": 1024`; without it you get the native 4096. Queries are `Instruct: <task>\nQuery: <q>`, documents go in plain. Vectors are L2-normalised, so dot product = cosine. |
| Rerank | `POST /cohere/v2/rerank` (Cohere v2) | `Qwen/Qwen3-Reranker-4B` | Body: `query`, `documents`, optional `top_n`, optional `instruction`. There's no OpenAI-style rerank route, and vLLM's `/score` isn't routed. |

## Deployment config

One pod on one Spark (scheduler-placed; dgx03 at rollout), with two
`vllm/vllm-openai:v0.32.0` containers sharing the pod's single `gpu`
ResourceClaim. Strategy `Recreate`.

| | embed (:8000) | rerank (:8001) |
|---|---|---|
| Checkpoint | `Qwen/Qwen3-Embedding-8B` @ `1d8ad4ca` (bf16, ~16 GB) | `Qwen/Qwen3-Reranker-4B` @ `22e68366` (bf16, ~8 GB) |
| Runner | `--runner pooling --convert embed` | `--runner pooling` |
| Overrides | `{"is_matryoshka": true}` (vLLM rejects `dimensions` without it) | `Qwen3ForSequenceClassification`, `classifier_from_token ["no","yes"]`, `is_original_qwen3_reranker`, plus the `reranker-template.jinja` chat template |
| `--gpu-memory-utilization` | 0.30 | 0.20 |
| `--max-model-len` | 8192 | 8192 |
| `--max-num-batched-tokens` | 16384 | 16384 |
| `--load-format` | instanttensor (it works with pooling models) | instanttensor |
| Memory limit | 48Gi | 48Gi |

- The GPU budgets are fractions of the ~120 GiB unified pool, so they add up:
  0.50 in total, which leaves ~60 GiB for the OS, page cache and kubelet.
- The rerank container waits for embed's `/health` before it loads. vLLM
  measures its non-torch memory as the change in device usage during its own
  startup, so a sibling loading at the same time would be counted against it.
- Weights are pinned HF commits, downloaded to the CephFS `models` PVC by the
  Flux-managed `qwen3-retrieval-weights` Job. An rclone init container copies
  them to node-local NVMe, and a second init container evicts them from page
  cache. Serving runs with `HF_HUB_OFFLINE=1` and passes `--revision` **and**
  `--tokenizer-revision`, because offline mode can't resolve `main`.
- Startup: about 162 s per server from container start to `/health` OK. The
  reranker starts after the embedder, so a cold pod is ready in about 5.5 min plus the init-container copy.
- Pooling models don't generate, so there's no torch.compile or cudagraph
  tuning to do.

## Verify (through the gateway, from an in-cluster pod)

From the one-shot `qwen3-retrieval-check` Job (script
`kubernetes/apps/inference/models/qwen3-retrieval/check/check.py` at a6a4e45,
removed afterwards; it's in git history). Run 2026-11-02 00:56Z:

```text
- embeddings (dimensions=1024): dims=[1024, 1024, 1024], norms=[1.0, 1.0, 1.0]
- cosine(query, relevant)=0.6685, cosine(query, irrelevant)=0.1453
- native dimension without `dimensions`: 4096
- rerank results: [(1, 0.8375), (0, 0.0)]

**VERIFY PASS**
```

The query was "What is the capital of France?" (with the instruct prefix),
the relevant passage was about Paris, and the irrelevant one was about
bananas. The reranker put the relevant document (index 1) first.

## Benchmark

Run 2026-11-02 00:56Z through the gateway, with both models loaded and
nothing else on the Spark. Every input is unique random text from a
~150-word vocabulary, so vLLM's prefix cache can't serve it. The engine
logged a 0.0% prefix-cache hit rate during the run. Token counts come from
the server's `usage`. Each embeddings row first runs one warm-up round of the
same shape, untimed.

### Embeddings (`dimensions: 1024`)

| tokens/input | inputs/request | concurrency | embeddings/s | tokens/s | p50 request s | p95 request s | max request s |
|---|---|---|---|---|---|---|---|
| ~104 | 32 | 4 | 48.7 | 5041 | 2.62 | 2.70 | 2.70 |
| ~411 | 32 | 4 | 13.4 | 5530 | 8.86 | 12.11 | 12.11 |
| ~821 | 16 | 4 | 6.7 | 5485 | 8.91 | 12.35 | 12.35 |
| ~412 | 1 | 1 | 6.8 | 2794 | 0.15 | 0.15 | 0.15 |
| ~411 | 1 | 16 | 12.1 | 4994 | 1.31 | 1.36 | 1.36 |

### Rerank

Sequential single requests, fresh candidates on every run. The query and
template prefix repeat, as they would in real use.

| candidates | tokens/candidate (incl. query + template) | p50 s | p95 s | max s | runs |
|---|---|---|---|---|---|
| 50 | ~288 | 1.24 | 1.27 | 1.27 | 20 |
| 50 | ~492 | 2.34 | 2.39 | 2.39 | 20 |
| 10 | ~287 | 0.27 | 0.30 | 0.30 | 20 |

### Reading it

- The embedder saturates at about **5,000–5,500 tokens/s** whenever
  requests are batched or concurrent, whatever the chunk size. Embeddings/s
  scales inversely with chunk length: ~49/s at ~100 tokens, ~13/s at ~400
  and ~7/s at ~800. 10,000 chunks of 400 tokens take about 13 minutes.
- A single sequential stream (one input per request, one in flight) gets
  about half that, ~2,800 tokens/s. For bulk indexing, send batches of
  16–32 inputs with a few requests in flight. 16 concurrent single-input
  requests also reach ~5,000 tokens/s.
- Query latency: one ~400-token query embeds in **0.15 s** end to end
  through the gateway, and a short query is faster.
- Rerank, 50 candidates: **1.24 s p50** at ~290 tokens per candidate (a
  ~200-word chunk plus the query and template), **2.34 s** at ~490. That is
  about 10–12k tokens/s, roughly linear in total tokens, so 10 candidates
  take 0.27 s. The engine logged a 15–22% prefix-cache hit rate here; that
  is the shared query and template prefix, as in real use.

### Known: cold-start tail

On the first rollout (2026-11-02 00:06Z), the first large concurrent batch
stalled: 4 concurrent requests of 32 × ~411 tokens all took about 84 s
(`duration_ms` ~83797 in the `ai` gateway log), and the embed engine logged
nothing in that window. The reranker had been up since 00:06:06, so it wasn't
the cause. The same shape ran in about 9–12 s on the next run, with no stall.
It looks like a one-off cold-path warm-up (kernel selection or allocation) on
the first big batch after startup. Clients should allow a generous timeout on
their first bulk request after a restart, or send a small warm-up batch.

### First run discarded

The first check run (00:06Z) reused about 42 distinct input strings, and the
engine logged 81–94% prefix-cache hits, so its throughput table measured the
cache, not the model. It was fixed in #2918 (unique inputs) before the run
above.
