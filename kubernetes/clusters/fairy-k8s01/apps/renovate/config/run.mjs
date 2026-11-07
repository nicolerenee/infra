// Mints a GitHub App installation token for the "Freckle Renovate" App's
// frecklelabs installation, then runs Renovate with it. Renovate can't mint
// tokens from an App key itself, and a token lasts an hour, so it is minted
// fresh at the start of every run.
//
// Env: GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY (Secret renovate-github-app).
import { spawnSync } from 'node:child_process';
import { createSign } from 'node:crypto';

const ORG = 'frecklelabs';
const API = 'https://api.github.com';
const { GITHUB_APP_ID: appId, GITHUB_APP_PRIVATE_KEY: key, ...env } = process.env;
if (!appId || !key) {
  console.error('GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY are required');
  process.exit(2);
}

function appJwt() {
  const now = Math.floor(Date.now() / 1000);
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const body = enc({ alg: 'RS256', typ: 'JWT' }) + '.' + enc({ iat: now - 60, exp: now + 540, iss: appId });
  return body + '.' + createSign('RSA-SHA256').update(body).sign(key, 'base64url');
}

async function github(method, path) {
  const res = await fetch(API + path, {
    method,
    headers: {
      Authorization: 'Bearer ' + appJwt(),
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!res.ok) throw new Error(method + ' ' + path + ': HTTP ' + res.status);
  return res.json();
}

// Renovate hands child processes (go mod tidy, npm and uv locks) only a
// fixed set of env plus customEnvVariables, so pass the package-proxy
// settings from cronjob.yaml along explicitly.
const PROXY_ENV = ['GOPROXY', 'GOSUMDB', 'GOPRIVATE', 'NPM_CONFIG_REGISTRY', 'PIP_INDEX_URL', 'UV_INDEX_URL'];
const proxyEnv = Object.fromEntries(PROXY_ENV.filter((k) => env[k]).map((k) => [k, env[k]]));

const inst = await github('GET', '/orgs/' + ORG + '/installation');
const { token } = await github('POST', '/app/installations/' + inst.id + '/access_tokens');
console.log('renovate: running for ' + ORG + ' (installation ' + inst.id + ')');
const run = spawnSync('renovate', [], {
  stdio: 'inherit',
  env: {
    ...env,
    RENOVATE_TOKEN: token,
    // postUpgradeTasks only see env Renovate is told to pass on; the
    // gateway-api vendor script calls `gh api` with GH_TOKEN.
    RENOVATE_CUSTOM_ENV_VARIABLES: JSON.stringify({ ...proxyEnv, GH_TOKEN: token }),
  },
});
process.exit(run.status ?? 1);
