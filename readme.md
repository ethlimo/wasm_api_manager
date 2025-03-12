limo_api_manager is a proof of concept WASM module server for dynamically executing server-side WASM bundles retrieved through standard dwebsite storage. This project is designed to allow for portable, transportable, gateway agnostic backends to dwebsites via automatic provisioning of webassembly worker payloads. 

# usage

limo_api_manager.exe --port 9000 --domain-suffix=".eth.limo" --domain-suffix-replacement=".eth" --dweb-api-url="http://localhost:9000"

# protocol

Compatible clients should be extism plugins stored as router.wasm in the root directory of the eth.limo compatible web3 storage gateway location of the ENS name. 

router.wasm is an executable that provides an http_json function that receives via stdin a json-encoded http_request (see lib/http_types.ml) end outputs via stdout a json-encoded http_response (lib/http_types.ml).

This server expects a REST service (--dweb-api-url) that accepts HTTP GET requests that accept an ENSname via the Host HTTP header and return a JSON encoded dweb_api_response (lib/dweb_api_response.ml), such that (x-content-location ++ x-content-path ++ "/router.wasm") is the gateway URL of the wasm bundle for the ensname.

# security

This is alpha quality software. Do not expose this gateway to the internet. For testing purposes, there are no restrictions on host APIs accessable by the WASM module. It is recommended to test against a hard-coded shim dweb-api-url.