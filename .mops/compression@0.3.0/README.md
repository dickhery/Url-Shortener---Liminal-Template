## Motoko Compression

This is a fork of [deflate.mo](https://github.com/NatLabs/deflate.mo) by NatLabs. The original work and credit belongs to NatLabs - this fork is maintained at [https://github.com/edjCase/motoko_compression](https://github.com/edjCase/motoko_compression).

This is a compression library that implements the DEFLATE lossless compression algorithm for compressing data into the Gzip format. It is heavily inspired by the [libflate](https://github.com/sile/libflate) rust library.

## Usage

### Installation

```bash
    mops add compression
```

### Importing

```motoko
    import Gzip "mo:compression/Gzip";
```

- Compressing and decompressing small data (<= **1MB**)

```motoko
import Blob "mo:base/Blob";
import Text "mo:base/Text";

import Gzip "mo:compression/Gzip";

let gzip_encoder = Gzip.EncoderBuilder().build();
let gzip_decoder = Gzip.Decoder();

func compress_data(data: [Nat8]) : Gzip.EncodedResponse {
    gzip_encoder.encode(data);

    // returns the encoded response and resets the gzip_encoder
    gzip_encoder.finish();
};

func decode_data(compressed: Gzip.EncodedResponse) : Gzip.DecodedResponse {
    for (chunk in compressed.chunks.vals()){
        gzip_decoder.decode(chunk);
    };

    // returns the decoded response and resets the gzip_decoder
    gzip_decoder.finish();
};

let data = Blob.toArray(Text.encodeUtf8("Hello, world!"));

let compressed = compress_data(data);
let decompressed = decode_data(compressed);

assert (decompressed.bytes == data);

```

- Compressing / Decoding larger bytes of data ( > **1MB**)

Due to the instruction limit for a single canister call, this implementation needs to make multiple calls to the canister to compress or decode larger bytes.

```motoko
import Buffer "mo:base/Buffer";
import TrieMap "mo:base/TrieMap";
import Text "mo:base/Text";
import Principal "mo:base/Principal";

import Gzip "mo:compression/Gzip";
import Itertools "mo:itertools/Iter";

shared ({caller = owner}) actor class User() = self {
    let gzip_encoder = Gzip.EncoderBuilder().build();
    let gzip_decoder = Gzip.Decoder();

    let map = TrieMap.TrieMap<Text, Gzip.EncodedResponse>(Text.equal, Text.hash);

    func canister_id() : Principal { Principal.fromActor(self) };

    // public canister async function that allows us make multiple calls to compress chunks of data
    public shared ({caller}) func compress(chunk: [Nat8]) : async () {
        assert caller == canister_id();

        gzip_encoder.encode(chunk);
    };

    // public canister async function that allows us make multiple calls to decode chunks of compressed data
    public shared ({caller}) func decode(chunk: [Nat8]) : async () {
        assert caller == canister_id();
        gzip_decoder.decode(chunk);
    };

    // compresses all the data irrespective of the size
    func compress_data(data : [Nat8]) : async* Gzip.EncodedResponse {
        let chunks_iter = Itertools.chunks(data.vals(), gzip_encoder.block_size());

        for (chunk in chunks_iter){
            await compress(chunk);
        };

        // returns the encoded response and resets the encoder
        let compressed = gzip_encoder.finish();

        return compressed;
    };

    // decodes all the compressed data irrespective of the size
    func decode_data(compressed: Gzip.EncodedResponse) : async* [Nat8] {

        for (chunk in compressed.chunks.vals()){
            await decode(chunk);
        };

        // returns the decoded response and resets the decoder
        let decoded_response =  gzip_decoder.finish();

        return Buffer.toArray(decoded_response.buffer);
    };

    public func store_image(name : Text, image: [Nat8]) : async () {
        let compressed = await* compress_data(image);
        map.put(name, compressed);
    };

    public func is_exact_image(name: Text, new_image : [Nat8]) : async Bool {
        let ?compressed = map.get(name) else return false;
        let stored_image = await* decode_data(compressed);

        return stored_image == new_image;
    };
};
```

## Resources

[Deflate's RFC Standard](https://www.rfc-editor.org/rfc/rfc1951#section-1.5)

[Implementation in rust (libflate)](https://github.com/sile/libflate)

Data Compression Lectures: [Lempel-Ziv Schemes](https://www.youtube.com/watch?v=VDXBnmr8AY0&list=PLU4IQLU9e_OpnkbCS_to64F_vw5yyg4HB&index=4) and [DEFLATE (gzip)](https://www.youtube.com/watch?v=oi2lMBBjQ8s&t=4038s)

[gstat - tool for analyzing gzip results](https://github.com/billbird/gzstat/blob/master/gzstat.py)
