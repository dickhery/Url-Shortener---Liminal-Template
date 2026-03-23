import Array "mo:base@0/Array";
import Blob "mo:base@0/Blob";
import Buffer "mo:base@0/Buffer";
import Debug "mo:base@0/Debug";
import Option "mo:base@0/Option";
import Int "mo:base@0/Int";
import Iter "mo:base@0/Iter";
import Nat16 "mo:base@0/Nat16";
import Nat32 "mo:base@0/Nat32";
import Text "mo:base@0/Text";
import Result "mo:base@0/Result";
import Time "mo:base@0/Time";

import BitBuffer "mo:bitbuffer@1/BitBuffer";
import CRC32 "../libs/CRC32";

import Deflate "../Deflate";
import Lzss "../LZSS";
import Header "Header";
import BitReader "../BitReader";

import { nat_to_le_bytes; le_bytes_to_nat } "../utils";

module {
  type Buffer<A> = Buffer.Buffer<A>;
  type BitBuffer = BitBuffer.BitBuffer;
  type Header = Header.Header;
  type DeflateOptions = Deflate.DeflateOptions;

  public type DecodedResponse = {
    filename : Text;
    comment : Text;
    mtime : Time.Time;
    fields : [Header.ExtraField];
    buffer : Buffer<Nat8>;
  };

  /// Gzip Decoder class
  /// Requires that the full header is available in the `init_bytes` array before initialization
  public class Decoder() {
    let reader = BitReader.fromBytes([]);

    var buffer = Buffer.Buffer<Nat8>(8);
    var opt_header : ?Header = null;
    let crc32_builder = CRC32.CRC32();
    var deflate_decoder = Deflate.Decoder(reader, ?buffer);
    var update_index = 0;

    private func decode_header() : Header {

      if (reader.readByte() != 0x1f or reader.readByte() != 0x8b) {
        Debug.trap("Invalid gzip magic number in header");
      };

      if (reader.readByte() != 0x08) {
        Debug.trap("Invalid compression method in header");
      };

      let is_text = reader.readBit();
      let is_verified = reader.readBit();

      let has_extra_fields = reader.readBit();
      let has_filename = reader.readBit();
      let has_comment = reader.readBit();
      ignore reader.readBits(3);

      let mtime = le_bytes_to_nat(reader.readBytes(4));
      let compression_level = Header.byteToCompressionLevel(reader.readByte());
      let os = Header.byteToOs(reader.readByte());

      let extra_fields = switch (has_extra_fields) {
        case (false) { [] };
        case (true) {
          let extra_fields = Buffer.Buffer<Header.ExtraField>(8);
          let extra_fields_size_as_bytes = reader.readBytes(2);
          let extra_fields_size = le_bytes_to_nat(extra_fields_size_as_bytes);

          var bytes_traversed = 0;

          while (bytes_traversed < extra_fields_size) {
            let ids = (reader.readByte(), reader.readByte());
            let size = le_bytes_to_nat(reader.readBytes(2));

            let data = reader.readBytes(size);
            bytes_traversed += 2 + 2 + size;

            let field : Header.ExtraField = { ids; data };
            extra_fields.add(field);
          };

          Buffer.toArray(extra_fields);
        };
      };

      func read_null_terminated_text() : ?Text {
        let bytes = Buffer.Buffer<Nat8>(8);
        var byte = reader.readByte();

        while (byte != 0) {
          bytes.add(byte);
          byte := reader.readByte();
        };

        let arr = Buffer.toArray(bytes);
        Text.decodeUtf8(Blob.fromArray(arr));
      };

      let filename = switch (has_filename) {
        case (false) null;
        case (true) read_null_terminated_text();
      };

      let comment = switch (has_comment) {
        case (false) null;
        case (true) read_null_terminated_text();
      };

      if (is_verified) {
        let crc16 = le_bytes_to_nat(reader.readBytes(2));

        let nbits_read = reader.getPosition();
        let nbytes_read = nbits_read / 8;

        reader.reset();
        let bytes = reader.readBytes(nbytes_read);
        let calculated_crc32 = CRC32.checksum(bytes);
        let calculated_crc16 = Nat32.toNat(calculated_crc32 & 0xffff);

        if (crc16 != calculated_crc16) {
          Debug.trap("Gzip Decoder: CRC16 Header verification mismatch");
        };
      };

      {
        is_text;
        is_verified;
        extra_fields;
        filename;
        comment;
        modification_time = ?mtime;
        compression_level;
        os;
      } : Header;
    };

    public func decode(bytes : [Nat8]) {
      reader.addBytes(bytes);

      if (opt_header == null) {
        opt_header := ?decode_header();
        reader.clearRead();
      };

      let res = deflate_decoder.decode();

      switch (res) {
        case (#ok(_)) {};
        case (#err(msg)) Debug.trap("Gzip Decoder Error: " # msg);
      };

      for (i in Iter.range(update_index + 1, buffer.size())) {
        crc32_builder.updateByte(buffer.get(i - 1));
        update_index += 1;
      };

      reader.clearRead();
    };

    public func clear() {

      opt_header := null;
      update_index := 0;

      reader.clear();

      buffer := Buffer.Buffer<Nat8>(8);
      deflate_decoder := Deflate.Decoder(reader, ?buffer);

    };

    public func finish() : DecodedResponse {
      let res = deflate_decoder.finish();
      switch (res) {
        case (#ok(_)) {};
        case (#err(msg)) Debug.trap("Gzip Decoder Error: " # msg);
      };

      for (i in Iter.range(update_index + 1, buffer.size())) {
        crc32_builder.updateByte(buffer.get(i - 1));
        update_index += 1;
      };

      // Debug.print("Gzip Decoder: Finished decoding");
      // Debug.print("remaining bits: " # debug_show(reader.bitSize()));
      reader.byteAlign();

      let calc_crc32 = crc32_builder.finish();

      let crc32 = (le_bytes_to_nat(reader.readBytes(4)));

      if (crc32 != Nat32.toNat(calc_crc32)) {
        Debug.trap("Gzip Decoder: CRC32 Footer verification mismatch");
      };

      let input_size = le_bytes_to_nat(reader.readBytes(4));

      if (buffer.size() != input_size) {
        Debug.trap("Gzip Decoder: Input size mismatch");
      };

      let output_buffer = buffer;

      let opt = do ? {
        let header = opt_header!;

        let response : DecodedResponse = {
          filename = Option.get(header.filename, "");
          comment = Option.get(header.comment, "");
          mtime = header.modification_time!;
          fields = header.extra_fields;
          buffer = output_buffer;
        };
      };

      clear();

      switch (opt) {
        case (?res) return res;
        case (_) Debug.trap("Gzip Error: Cannot create a DecodedResponse because the Gzip header is missing");
      };

    };

  };
};
