/// Default public server (VPS) when the user has not saved a URL in settings.
/// Direct IPv4 VPS access. Use HTTP unless you configure a valid certificate.
const String kDefaultIotServerUrl = 'http://103.116.38.192';

/// FastAPI AI service on VPS (port 8000). App gọi thêm `/predict`.
const String kDefaultAiServerUrl = 'http://103.116.38.192:8000';

/// REST + Socket use the same `X-API-KEY` as the Node server `API_KEY` in `.env`.
/// Relay IDs expected by the backend (`relay.js`): 1 = shade/màn che, 2 = pump/bơm.
const int kRelayIdShade = 1;
const int kRelayIdPump = 2;
