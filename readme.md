limo_api_manager is a proof of concept WASM module server for dynamically executing server-side WASM bundles retrieved through standard dwebsite storage. This library uses the dweb_api content resolution API to resolve ENSnames to web3 storage gateways to retrieve a router.wasm Extism plugin.

router.wasm is an executable that provides an http_json function that receives via stdin a json-encoded http_request (see lib/http_types.ml) end outputs via stdout a json-encoded http_response (lib/http_types.ml).

This server expects a REST service (--dweb-api-url) that accepts HTTP GET requests that accept an ENSname via the Host HTTP header and return a JSON encoded dweb_api_response (lib/dweb_api_response.ml), such that (x-content-location ++ x-content-path ++ "/router.wasm") is the gateway URL of the wasm bundle for the ensname.

# usage

limo_api_manager.exe --port 9000 --domain-suffix=".eth.limo" --domain-suffix-replacement=".eth" --dweb-api-url="http://localhost:9000"