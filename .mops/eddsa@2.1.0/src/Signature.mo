import Nat "mo:core@1/Nat";
import Nat8 "mo:core@1/Nat8";
import Buffer "mo:buffer@0";
import Iter "mo:core@1/Iter";
import Result "mo:core@1/Result";
import BaseX "mo:base-x-encoder@2";
import NatX "mo:xtended-numbers@2/NatX";
import Int "mo:core@1/Int";
import Text "mo:core@1/Text";
import Runtime "mo:core@1/Runtime";
import Common "Common";
import ASN1 "mo:asn1@3";
import List "mo:core@1/List";

module {
  public type OutputByteEncoding = {
    #raw;
    #der;
  };

  public type InputByteEncoding = {
    #raw : {
      curve : CurveKind;
    };
    #der : {
      curve : CurveKind;
    };
  };

  public type OutputTextFormat = {
    #base64 : {
      byteEncoding : OutputByteEncoding;
      format : BaseX.Base64OutputFormat;
    };
    #hex : {
      byteEncoding : OutputByteEncoding;
      format : BaseX.HexOutputFormat;
    };
  };

  public type InputTextFormat = {
    #base64 : {
      byteEncoding : InputByteEncoding;
    };
    #hex : {
      byteEncoding : InputByteEncoding;
      format : BaseX.HexInputFormat;
    };
  };
  public type CurveKind = Common.CurveKind;

  public type Point = {
    x : Int;
    y : Nat;
  };

  public class Signature(
    x_ : Int,
    y_ : Nat,
    s_ : Nat,
  ) {
    public let x = x_;
    public let y = y_;
    public let s = s_;

    public func equal(other : Signature) : Bool {
      x == other.x and y == other.y and s == other.s;
    };

    public func toBytes(encoding : OutputByteEncoding) : [Nat8] {
      switch (encoding) {
        case (#raw) {
          let list = List.empty<Nat8>();
          let buffer = Buffer.fromList(list);
          // y
          NatX.toNatBytesBuffer(buffer, y, #lsb);
          while (List.size(list) < 32) {
            List.add<Nat8>(list, 0); // Pad with zeros
          };
          let final_byte_31 : Nat8 = if (x % 2 == 1) {
            // Odd x: SET the MSB
            List.at<Nat8>(list, 31) | 0x80;
          } else {
            // Even x: CLEAR the MSB
            List.at(list, 31) & 0x7F;
          };
          List.put(list, 31, final_byte_31);
          // s
          NatX.toNatBytesBuffer(buffer, s, #lsb);
          while (List.size(list) < 64) {
            List.add<Nat8>(list, 0); // Pad with zeros
          };
          List.toArray(list);
        };
        case (#der) {
          let list = List.empty<Nat8>();
          let buffer = Buffer.fromList(list);
          // y
          NatX.toNatBytesBuffer(buffer, y, #lsb);
          while (List.size(list) < 32) {
            List.add<Nat8>(list, 0); // Pad with zeros
          };
          let final_byte_31 : Nat8 = if (x % 2 == 1) {
            // Odd x: SET the MSB
            List.at(list, 31) | 0x80;
          } else {
            // Even x: CLEAR the MSB
            List.at(list, 31) & 0x7F;
          };
          List.put(list, 31, final_byte_31);
          let ?r = NatX.fromNatBytes(List.values(list), #lsb) else Runtime.trap("Failed to decode r");

          // Create the ASN.1 DER structure
          // SEQUENCE { INTEGER r, INTEGER s }
          let asn1Value : ASN1.ASN1Value = #sequence([
            #integer(r),
            #integer(s),
          ]);

          // Encode to DER format
          ASN1.toBytes(asn1Value, #der);
        };
      };
    };

    // Convert signature to text representation
    public func toText(format : OutputTextFormat) : Text {
      switch (format) {
        case (#hex(hex)) {
          let bytes = toBytes(hex.byteEncoding);
          BaseX.toHex(bytes.vals(), hex.format);
        };
        case (#base64(base64)) {
          let bytes = toBytes(base64.byteEncoding);
          BaseX.toBase64(bytes.vals(), base64.format);
        };
      };
    };
  };

  public func fromBytes(
    bytes : Iter.Iter<Nat8>,
    encoding : InputByteEncoding,
  ) : Result.Result<Signature, Text> {
    switch (encoding) {
      case (#raw({ curve })) {
        let rBytes = bytes |> Iter.take(_, 32) |> List.fromIter<Nat8>(_);
        let isXNegative = List.at(rBytes, 31) & 0x80 == 0x80;
        if (isXNegative) {
          // Clear the sign bit for negative x
          List.put(rBytes, 31, List.at(rBytes, 31) & 0x7F);
        };
        let ?y = NatX.fromNatBytes(List.values(rBytes), #lsb) else return #err("Invalid signature bytes, unable to decode R");
        let x : Int = Common.recoverXFromY(y, curve, isXNegative);
        let ?s = NatX.fromNatBytes(bytes, #lsb) else return #err("Invalid signature bytes, unable to decode s");

        #ok(Signature(x, y, s));
      };
      case (#der({ curve })) {
        // Try to decode the DER bytes as ASN.1
        let asn1Result = ASN1.fromBytes(bytes, #der);
        switch (asn1Result) {
          case (#err(e)) {
            return #err("Failed to decode DER: " # e);
          };
          case (#ok(asn1)) {
            // Check if it's a SEQUENCE
            let #sequence(seq) = asn1 else {
              return #err("Expected ASN.1 SEQUENCE, got something else");
            };

            // Check if it has exactly 2 elements (r and s)
            if (seq.size() != 2) {
              return #err("Expected SEQUENCE with 2 elements, got " # Nat.toText(seq.size()));
            };

            // Check if both elements are INTEGERs
            let #integer(rInt) = seq[0] else {
              return #err("Expected INTEGER for R component");
            };

            let #integer(sInt) = seq[1] else {
              return #err("Expected INTEGER for S component");
            };

            // Convert back to integer values
            // Convert R to little-endian bytes for our internal representation
            let list = List.empty<Nat8>();
            let rBuffer = Buffer.fromList(list);
            NatX.toNatBytesBuffer(rBuffer, Int.abs(rInt), #lsb);
            while (List.size(list) < 32) {
              List.add<Nat8>(list, 0);
            };

            // Extract the sign bit and recover x
            let isXNegative = rInt < 0;
            let final_byte_31 : Nat8 = if (isXNegative) {
              List.at(list, 31) | 0x80;
            } else {
              List.at(list, 31) & 0x7F;
            };
            List.put<Nat8>(list, 31, final_byte_31);

            let ?y = NatX.fromNatBytes(List.values(list), #lsb) else {
              return #err("Invalid R component");
            };

            let x : Int = Common.recoverXFromY(y, curve, isXNegative);

            // Get the S value directly
            let s = Int.abs(sInt);

            #ok(Signature(x, y, s));
          };
        };
      };
    };
  };

  public func fromText(
    value : Text,
    encoding : InputTextFormat,
  ) : Result.Result<Signature, Text> {
    switch (encoding) {
      case (#hex({ format; byteEncoding })) {
        // Convert hex to bytes
        switch (BaseX.fromHex(value, format)) {
          case (#ok(bytes)) {
            switch (fromBytes(bytes.vals(), byteEncoding)) {
              case (#ok(signature)) #ok(signature);
              case (#err(e)) #err("Invalid signature bytes: " # e);
            };
          };
          case (#err(e)) #err("Invalid hex format: " # e);
        };
      };
      case (#base64({ byteEncoding })) {
        // Convert base64 to bytes
        switch (BaseX.fromBase64(value)) {
          case (#ok(bytes)) {
            switch (fromBytes(bytes.vals(), byteEncoding)) {
              case (#ok(signature)) #ok(signature);
              case (#err(e)) #err("Invalid signature bytes: " # e);
            };
          };
          case (#err(e)) #err("Invalid base64 format: " # e);
        };
      };
    };
  };
};
