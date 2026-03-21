[![mops](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/mops/http-types)](https://mops.one/http-types)
[![documentation](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/documentation/http-types)](https://mops.one/http-types/docs)

# Canister HTTP interface types

More https://internetcomputer.org/docs/current/references/http-gateway-protocol-spec/

## Install
```
mops add http-types
```

## Usage
```motoko
import HttpTypes "mo:http-types";
import Text "mo:base/Text";

public query func http_request(request : HttpTypes.Request) : async HttpTypes.Response {
  return {
    status_code = 200;
    headers = [
      ("Content-Type", "text/html; charset=utf-8"),
    ];
    body = Text.encodeUtf8("Hello, <b>World!</b>");
    streaming_strategy = null;
    upgrade = null;
  };
}
```

## HTTP outcalls

HTTP outcalls have slightly different types than inbound HTTP calls.

Use the [ic](https://mops.one/ic) Motoko package for HTTP outcalls. [Docs](https://mops.one/ic/docs#type.HttpHeader)