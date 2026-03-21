import Buffer "mo:base@0/Buffer";
import Deque "mo:base@0/Deque";
import LZSSEncoder "Encoder";
import LzssDecoder "Decoder";

import Common "Common";

module {
  type Buffer<A> = Buffer.Buffer<A>;
  public type LzssEntry = Common.LzssEntry;

  public func encode(bytes : [Nat8]) : Buffer<LzssEntry> = LZSSEncoder.encode(bytes);

  public type Encoder = LZSSEncoder.Encoder;
  public let Encoder = LZSSEncoder.Encoder;

  public let decode = LzssDecoder.decode;

  public type Decoder = LzssDecoder.Decoder;
  public let Decoder = LzssDecoder.Decoder;
};
