import Buffer "mo:base@0/Buffer";
import Blob "mo:base@0/Blob";
import Iter "mo:base@0/Iter";
import Option "mo:base@0/Option";
import Int "mo:base@0/Int";
import Nat32 "mo:base@0/Nat32";
import Nat64 "mo:base@0/Nat64";
import Text "mo:base@0/Text";
import Time "mo:base@0/Time";

import CRC32 "../libs/CRC32";
import BitBuffer "mo:bitbuffer@1/BitBuffer";

import { nat_to_le_bytes; INSTRUCTION_LIMIT } "../utils";

module Header {
  type BitBuffer = BitBuffer.BitBuffer;
  type Buffer<A> = Buffer.Buffer<A>;
  type Time = Time.Time;

  public type ExtraField = {
    ids : (Nat8, Nat8);

    /// The data of the extra field.
    /// If the data is a number, it has to be stored with the least significant byte first.
    data : [Nat8];
  };

  public type CompressionLevel = {
    #Fastest;
    #Slowest;
    #Unknown;
  };

  public type Os = {
    /// FAT filesystem (MS-DOS, OS/2, NT/Win32)
    #FatFs;

    ///Amiga
    #Amiga;

    /// VMS (or OpenVMS)
    #Vms;

    /// Unix
    #Unix;

    /// VM/CMS
    #VmCms;

    /// Atari TOS
    #AtariTos;

    /// HPFS filesystem (OS/2, NT)
    #Hpfs;

    /// Macintosh
    #Macintosh;

    /// Z-System
    #ZSystem;

    /// CP/M
    #CpM;

    /// TOPS-20
    #Tops20;

    /// NTFS filesystem (NT)
    #Ntfs;

    /// QDOS
    #Qdos;

    /// Acorn RISCOS
    #AcornRiscos;

    /// unknown
    #Unknown;
  };

  public type Header = {
    is_text : Bool;
    is_verified : Bool;
    extra_fields : [ExtraField];
    filename : ?Text;
    comment : ?Text;
    modification_time : ?Time;
    compression_level : CompressionLevel;
    os : Os;
  };

  public func defaultHeaderOptions() : Header = {
    is_text = false;
    is_verified = false;
    extra_fields = [];
    filename = null;
    comment = null;
    modification_time = ?Time.now();
    compression_level = #Unknown;
    os = #Unix;
  };

  public func encode(bitbuffer : BitBuffer, header : Header) {
    // Add Header bytes to the bitbuffer
    // - magic header
    BitBuffer.addByte(bitbuffer, 0x1f);
    BitBuffer.addByte(bitbuffer, 0x8b);

    // - compression method: deflate
    BitBuffer.addByte(bitbuffer, 8);

    // - flags
    bitbuffer.addBit(header.is_text);
    bitbuffer.addBit(header.is_verified);
    bitbuffer.addBit(header.extra_fields.size() > 0);
    bitbuffer.addBit(Option.isSome(header.filename));
    bitbuffer.addBit(Option.isSome(header.comment));
    bitbuffer.byteAlign();

    // - modification time
    let mtime = switch (header.modification_time) {
      case (?t) { t };
      case (_) { Time.now() / 10 ** 9 };
    };

    let mtime_nat = Int.abs(mtime);
    BitBuffer.addBytes(bitbuffer, nat_to_le_bytes(mtime_nat, 4));

    // - compression method flags
    let compression_level = Header.compressionLevelToByte(header.compression_level);
    BitBuffer.addByte(bitbuffer, compression_level);

    // - operating system
    let os = Header.osToByte(header.os);
    BitBuffer.addByte(bitbuffer, os);

    // - extra fields
    let extra_fields = header.extra_fields;

    if (extra_fields.size() > 0) {
      var fields_total_size = 0;

      for ({ data } in header.extra_fields.vals()) {
        fields_total_size += (4 + data.size());
      };

      BitBuffer.addBytes(bitbuffer, nat_to_le_bytes(fields_total_size, 2));

      for (field in header.extra_fields.vals()) {
        BitBuffer.addByte(bitbuffer, field.ids.0);
        BitBuffer.addByte(bitbuffer, field.ids.1);

        BitBuffer.addBytes(bitbuffer, nat_to_le_bytes(field.data.size(), 2));
        BitBuffer.addBytes(bitbuffer, field.data);
      };
    };

    // - filename
    switch (header.filename) {
      case (?filename) {
        let bytes = Text.encodeUtf8(filename);
        BitBuffer.addBytes(bitbuffer, Blob.toArray(bytes));
        BitBuffer.addByte(bitbuffer, 0);
      };
      case (_) {};
    };

    // - comment
    switch (header.comment) {
      case (?comment) {
        let bytes = Text.encodeUtf8(comment);
        BitBuffer.addBytes(bitbuffer, Blob.toArray(bytes));
        BitBuffer.addByte(bitbuffer, 0);
      };
      case (_) {};
    };

    // - crc16
    if (header.is_verified) {
      let bytes = Iter.toArray(bitbuffer.bytes());

      let crc32 = CRC32.checksum(bytes);
      let crc16 = Nat32.toNat(crc32) % (2 ** 16);

      BitBuffer.addBytes(bitbuffer, nat_to_le_bytes(crc16, 2));
    };
  };

  public func compressionLevelToByte(compression_level : CompressionLevel) : Nat8 {
    switch (compression_level) {
      case (#Unknown) { 0x00 };
      case (#Slowest) { 0x02 };
      case (#Fastest) { 0x04 };
    };
  };

  public func byteToCompressionLevel(byte : Nat8) : CompressionLevel {
    switch (byte) {
      case (0x02) { #Slowest };
      case (0x04) { #Fastest };
      case (_) { #Unknown };
    };
  };

  public func osToByte(os : Os) : Nat8 = switch (os) {
    case (#FatFs) { 0x00 };
    case (#Amiga) { 0x01 };
    case (#Vms) { 0x02 };
    case (#Unix) { 0x03 };
    case (#VmCms) { 0x04 };
    case (#AtariTos) { 0x05 };
    case (#Hpfs) { 0x06 };
    case (#Macintosh) { 0x07 };
    case (#ZSystem) { 0x08 };
    case (#CpM) { 0x09 };
    case (#Tops20) { 0x0a };
    case (#Ntfs) { 0x0b };
    case (#Qdos) { 0x0c };
    case (#AcornRiscos) { 0x0d };
    case (#Unknown) { 0xff };
  };

  public func byteToOs(byte : Nat8) : Os = switch (byte) {
    case (0x00) { #FatFs };
    case (0x01) { #Amiga };
    case (0x02) { #Vms };
    case (0x03) { #Unix };
    case (0x04) { #VmCms };
    case (0x05) { #AtariTos };
    case (0x06) { #Hpfs };
    case (0x07) { #Macintosh };
    case (0x08) { #ZSystem };
    case (0x09) { #CpM };
    case (0x0a) { #Tops20 };
    case (0x0b) { #Ntfs };
    case (0x0c) { #Qdos };
    case (0x0d) { #AcornRiscos };
    case (_) { #Unknown };
  };

};
