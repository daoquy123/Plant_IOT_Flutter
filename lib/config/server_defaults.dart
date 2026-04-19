/// Default public server (VPS) when the user has not saved a URL in settings.
/// After HTTPS (Let's Encrypt) is enabled, set the app URL to `https://...` in Cài đặt.
const String kDefaultIotServerUrl = 'http://five-small-snowflake.site';

/// REST + Socket use the same `X-API-KEY` as the Node server `API_KEY` in `.env`.
/// Relay IDs expected by the backend (`relay.js`): 1 = shade/màn che, 2 = pump/bơm.
const int kRelayIdShade = 1;
const int kRelayIdPump = 2;
