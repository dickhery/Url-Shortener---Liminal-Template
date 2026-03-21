import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";

import {test; suite; skip} "mo:test";

import BitBuffer "../src/BitBuffer";

suite("BitBuffer", func() {

    test("init()", func(){
        let bitbuffer = BitBuffer.init(64, true);

        assert bitbuffer.bitcount(true) == 64;
        assert bitbuffer.bitcount(false) == 0;

        assert bitbuffer.bitSize() == 64;

    });

    test("Test getBit()", func(){
        let bitbuffer = BitBuffer.init(3, true);

        assert bitbuffer.getBit(0);
        assert bitbuffer.getBit(1);
        assert bitbuffer.getBit(2);

        bitbuffer.addBit(false);
        assert not bitbuffer.getBit(3);
    });

	test("Add bits to bitbuffer", func() {
        let bitbuffer = BitBuffer.BitBuffer(120);

        bitbuffer.addBits(2, 10);
        bitbuffer.addBits(16, 43690);
        bitbuffer.addBits(32, 2863311530);
        bitbuffer.addBits(64, 12297829382473034410);
        bitbuffer.addBits(6, 43690);

        assert bitbuffer.bitSize() == 120;
        assert bitbuffer.byteSize() == 15;

        let res_array = Iter.toArray(bitbuffer.bytes());
        assert res_array == [170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170];
    });

    test("Add bits v2", func() {
        let bitbuffer = BitBuffer.init(4, false);
        bitbuffer.addBits(9, 83);
        assert bitbuffer.getBits(4, 9) == 83;

        bitbuffer.clear();
        bitbuffer.addBits(9, 324);

        Debug.print(debug_show Iter.toArray(bitbuffer.bytes()));
        assert bitbuffer.getBits(0, 9) == 324;

    });

    test("Drop top bits from bitbuffer", func(){
        let bitbuffer = BitBuffer.BitBuffer(120);
        bitbuffer.addBits(120, 226854911280625642308916404954512140970);

        assert bitbuffer.bitSize() == 120;
        assert bitbuffer.byteSize() == 15;

        bitbuffer.dropBits(8);
        assert bitbuffer.bitSize() == 112;
        assert bitbuffer.byteSize() == 14;

        bitbuffer.dropBits(7);

        assert bitbuffer.bitSize() == 105;
        assert bitbuffer.byteSize() == 14;

        bitbuffer.dropBits(22);

        assert bitbuffer.bitSize() == 83;
        assert bitbuffer.byteSize() == 11;

        bitbuffer.dropBits(3);

        assert bitbuffer.bitSize() == 80;
        assert bitbuffer.byteSize() == 10;

        bitbuffer.dropBits(41);

        assert bitbuffer.bitSize() == 39;
        assert bitbuffer.byteSize() == 5;

        assert Iter.toArray(bitbuffer.bytes()) == [170, 170, 170, 170, 170];

        bitbuffer.dropBits(39);
        assert bitbuffer.bitSize() == 0;

        bitbuffer.addBits(1, 1);
        assert bitbuffer.bitSize() == 1;

        assert bitbuffer.getBit(0);
    });

    
    test("Test getBits()", func(){
        let bitbuffer = BitBuffer.BitBuffer(120);
        bitbuffer.addBits(120, 226854911280625642308916404954512140970);

        assert bitbuffer.getBits(0, 2) == 2;
        assert bitbuffer.getBits(0, 6) == 42;

        assert bitbuffer.getBits(1, 2) == 1;
        assert bitbuffer.getBits(1, 6) == 21;


        assert bitbuffer.getBits(5, 2) == 1;
        assert bitbuffer.getBits(5, 5) == 21;
        assert bitbuffer.getBits(5, 6) == 21;
        assert bitbuffer.getBits(5, 6) == 21;
        assert bitbuffer.getBits(5, 7) == 85;

        assert bitbuffer.getBits(5, 100) == 422550200076076467165567735125;

    });

    test("getBits() t2", func(){
        let bitbuffer = BitBuffer.fromBytes([0xf3, 0x48]);
        assert bitbuffer.getBits(3, 5) == 30;
        assert bitbuffer.getBits(8, 3) == 0;
        assert bitbuffer.getBits(3, 8) == 30;
    });
    
    test("addBit()", func(){
        let bitbuffer = BitBuffer.init(8, true);

        assert bitbuffer.bitcount(true) == 8;
        assert bitbuffer.getBit(0) == true;

        bitbuffer.addBit(false);
        bitbuffer.addBit(true);
        bitbuffer.addBit(false);

        assert bitbuffer.getBit(8) == false;
        assert bitbuffer.getBit(9) == true;
        assert bitbuffer.getBit(10) == false;

        assert bitbuffer.bitSize() == 11;
    });
});