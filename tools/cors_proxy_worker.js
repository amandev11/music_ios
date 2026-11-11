// Cloudflare Worker: GET /?url=<encoded target> -> target response with permissive CORS.
// Only the hosts below are reachable, so the worker is not an open proxy.
const ALLOWED = ['www.jiosaavn.com', 'lrclib.net', 'yewtu.be', 'inv.nadeko.net', 'invidious.nerdvpn.de'];

export default {
  async fetch(request) {
    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
    };
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });
    const target = new URL(request.url).searchParams.get('url');
    if (!target) return new Response('missing url', { status: 400, headers: cors });
    let u;
    try { u = new URL(target); } catch { return new Response('bad url', { status: 400, headers: cors }); }
    if (u.protocol !== 'https:' || !ALLOWED.includes(u.hostname)) {
      return new Response('host not allowed', { status: 403, headers: cors });
    }
    const upstream = await fetch(u.toString(), {
      headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/134.0 Safari/537.36', 'Cookie': 'explicit_content=1' },
    });
    const headers = new Headers(upstream.headers);
    for (const [k, v] of Object.entries(cors)) headers.set(k, v);
    return new Response(upstream.body, { status: upstream.status, headers });
  },
};
