import Buffer "mo:base@0/Buffer";
import Iter "mo:base@0/Iter";
import Nat "mo:base@0/Nat";

import BitBuffer "mo:bitbuffer@1/BitBuffer";
import BitReader "../BitReader";
import Symbol "Symbol";
import DeflateEncoder "Encoder";
import DeflateDecoder "Decoder";
import LZSS "../LZSS";
import LzssEncoder "../LZSS/Encoder";

module {
  type Buffer<A> = Buffer.Buffer<A>;
  type BitBuffer = BitBuffer.BitBuffer;
  type BitReader = BitReader.BitReader;

  type Iter<A> = Iter.Iter<A>;
  type LzssEntry = LZSS.LzssEntry;
  type LzssEncoder = LzssEncoder.Encoder;
  type Symbol = Symbol.Symbol;

  public type Encoder = DeflateEncoder.Encoder;
  public let Encoder : (BitBuffer, DeflateOptions) -> DeflateEncoder.Encoder = DeflateEncoder.Encoder;

  public type Decoder = DeflateDecoder.Decoder;
  public let Decoder : (BitReader, ?Buffer<Nat8>) -> DeflateDecoder.Decoder = DeflateDecoder.Decoder;

  public func buildEncoder(
    options : DeflateOptions
  ) : Encoder {
    let bitBuffer = BitBuffer.BitBuffer(8);
    Encoder(bitBuffer, options);
  };

  public func buildDecoder(
    buffer : ?Buffer<Nat8>
  ) : Decoder {
    let reader = BitReader.BitReader();
    Decoder(reader, buffer);
  };

  public type DeflateOptions = {
    block_size : Nat;
    dynamic_huffman : Bool;
    lzss : ?LzssEncoder;
  };

};
