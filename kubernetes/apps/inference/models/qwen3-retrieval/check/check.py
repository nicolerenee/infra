# Verify + benchmark for qwen3-retrieval through the ai gateway (C-349).
# stdlib only; prints a markdown report to stdout.
import itertools, json, math, random, statistics, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

GW = "http://ai-gateway.inference.svc.cluster.local"
EMB = "Qwen/Qwen3-Embedding-8B"
RR = "Qwen/Qwen3-Reranker-4B"
TASK = "Given a web search query, retrieve relevant passages that answer the query"


def post(path, body, timeout=600):
    req = urllib.request.Request(GW + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.load(r)
    return out, time.perf_counter() - t


def wait_ready():
    for _ in range(120):
        try:
            post("/v1/embeddings", {"model": EMB, "input": "ping", "dimensions": 1024}, 30)
            post("/cohere/v2/rerank", {"model": RR, "query": "q", "documents": ["d"]}, 30)
            return
        except Exception as e:  # noqa: BLE001
            print("not ready yet:", e, flush=True)
            time.sleep(15)
    raise SystemExit("gateway routes never became ready")


def cos(a, b):
    return sum(x * y for x, y in zip(a, b))


# Filler text: random draws from a ~150-word vocabulary, ~1.3 tokens/word.
# Every input in the run is distinct from its first words on, so vLLM's
# prefix cache can't serve it (a first version reused ~42 strings and measured
# 80-95% cache hits, not model throughput). Real token counts come from the
# server's usage numbers.
WORDS = """the a of to and in on for with from by at as is was are were be been
has have had not but or so if then when because while after before until
backup job storage cluster failed overnight snapshot schedule overlapped weekly
scrub pool ran low space operator paused replication morning alert cleared
queue drained normally again node disk network latency packet route gateway
certificate expired renewed deploy rollout image registry pulled container
restart crash memory limit pressure evicted pod service endpoint ingress dns
record resolver timeout retry database index query slow vacuum table lock
migration schema version upgrade release notes breaking change config value
secret token rotation policy access denied user group role permission audit
log metric trace dashboard panel threshold page incident review followup
owner team ticket priority week month quarter plan budget cost estimate
model weights inference request batch token latency throughput gpu cache
vector search document chunk embedding rerank score relevant answer question
""".split()
_seq = itertools.count()


def text(n_words):
    r = random.Random(next(_seq))
    return " ".join(r.choice(WORDS) for _ in range(n_words))


def verify():
    print("## Verify\n")
    q = f"Instruct: {TASK}\nQuery: What is the capital of France?"
    docs = ["Paris is the capital and largest city of France.",
            "Bananas are a good source of potassium."]
    out, _ = post("/v1/embeddings", {"model": EMB, "input": [q] + docs, "dimensions": 1024})
    v = [d["embedding"] for d in out["data"]]
    dims = [len(x) for x in v]
    norms = [math.sqrt(cos(x, x)) for x in v]
    s_rel, s_irr = cos(v[0], v[1]), cos(v[0], v[2])
    print(f"- embeddings (dimensions=1024): dims={dims}, norms={[round(n, 4) for n in norms]}")
    print(f"- cosine(query, relevant)={s_rel:.4f}, cosine(query, irrelevant)={s_irr:.4f}")
    full, _ = post("/v1/embeddings", {"model": EMB, "input": "hello"})
    print(f"- native dimension without `dimensions`: {len(full['data'][0]['embedding'])}")
    rr, _ = post("/cohere/v2/rerank", {"model": RR, "query": "What is the capital of France?",
                                        "documents": [docs[1], docs[0]]})
    res = rr["results"]
    print(f"- rerank results: {[(r['index'], round(r['relevance_score'], 4)) for r in res]}")
    ok = (dims == [1024] * 3 and all(abs(n - 1) < 1e-3 for n in norms)
          and s_rel > s_irr and res[0]["index"] == 1)
    print(f"\n**VERIFY {'PASS' if ok else 'FAIL'}**\n")
    return ok


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))]


def bench_embed(words, batch, conc, requests):
    def one(inp):
        out, dt = post("/v1/embeddings", {"model": EMB, "input": inp, "dimensions": 1024})
        toks.append(out["usage"]["prompt_tokens"])
        return dt

    # Warm-up: one full concurrent round of the same shape on throwaway inputs.
    toks = []
    with ThreadPoolExecutor(conc) as ex:
        list(ex.map(one, [[text(words) for _ in range(batch)] for _ in range(conc)]))
    inputs = [[text(words) for _ in range(batch)] for _ in range(requests)]
    toks = []
    t = time.perf_counter()
    with ThreadPoolExecutor(conc) as ex:
        lat = list(ex.map(one, inputs))
    wall = time.perf_counter() - t
    n = batch * requests
    return (f"| ~{sum(toks) / n:.0f} | {batch} | {conc} | {n / wall:.1f} | "
            f"{sum(toks) / wall:.0f} | {statistics.median(lat):.2f} | "
            f"{pct(lat, 0.95):.2f} | {max(lat):.2f} |")


def bench_rerank(doc_words, n_docs, runs):
    # Fresh candidates every run (a real query brings new documents); the
    # query and template prefix repeat, as they do in real use.
    q = "why did the overnight backup fail on the storage cluster"
    post("/cohere/v2/rerank", {"model": RR, "query": q,
                               "documents": [text(doc_words) for _ in range(n_docs)]})  # warm
    lat, toks = [], 0
    for _ in range(runs):
        docs = [text(doc_words) for _ in range(n_docs)]
        out, dt = post("/cohere/v2/rerank", {"model": RR, "query": q, "documents": docs})
        lat.append(dt)
        toks = out.get("usage", {}).get("total_tokens", 0) or toks
    return (f"| {n_docs} | ~{toks / n_docs:.0f} | {statistics.median(lat):.2f} | "
            f"{pct(lat, 0.95):.2f} | {max(lat):.2f} | {runs} |")


wait_ready()
ok = verify()
print("## Embeddings throughput (dimensions=1024, unique inputs)\n")
print("| tokens/input | inputs/request | concurrency | embeddings/s | tokens/s "
      "| p50 request s | p95 request s | max request s |")
print("|---|---|---|---|---|---|---|---|")
for words, batch, conc, reqs in [(100, 32, 4, 24), (400, 32, 4, 16), (800, 16, 4, 16),
                                 (400, 1, 1, 30), (400, 1, 16, 96)]:
    print(bench_embed(words, batch, conc, reqs), flush=True)
print("\n## Rerank latency (single request, sequential, fresh candidates)\n")
print("| candidates | tokens/candidate (incl. query+template) | p50 s | p95 s | max s | runs |")
print("|---|---|---|---|---|---|")
for doc_words, n in [(200, 50), (400, 50), (200, 10)]:
    print(bench_rerank(doc_words, n, 20), flush=True)
raise SystemExit(0 if ok else 1)
