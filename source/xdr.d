/*
 *  XDR - A D language implementation of the External Data Representation
 *  Copyright (C) 2015 Paul O'Neil
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

//! Provides an implementation of RFC 4506.
module xdr;

import std.algorithm : copy, map;
import std.bitmanip;
import std.range;
import std.traits;

version (unittest)
{
    import std.exception : assertThrown;
}

ref Output put(T, Output)(ref Output output, T val)
    if (isOutputRange!(Output, ubyte)
        && T.sizeof % 4 == 0 && (isIntegral!T || isFloatingPoint!T))
{
    std.range.put(output, nativeToBigEndian(val)[]);
    return output;
}

ref Output put(T: bool, Output)(ref Output output, bool val)
    if (isOutputRange!(Output, ubyte))
{
    if (val)
    {
        output.put!int(1);
    }
    else
    {
        output.put!int(0);
    }

    return output;
}
// The existence of this method seems to solve const/overload problems
ref Output put(Output)(ref Output output, bool val) if (isOutputRange!(Output, ubyte))
{
    return output.put!bool(val);
}

ref Output put(ulong len, Output)(ref Output output, in ubyte[len] data)
    if (isOutputRange!(Output, ubyte) && len % 4 == 0)
{
    std.range.put(output, data[]);
    return output;
}

ref Output put(ulong len, Output)(ref Output output, in ubyte[len] data)
    if (isOutputRange!(Output, ubyte) && len % 4 != 0)
{
    std.range.put(output, data[]);
    enum padding = 4 - (len % 4);
    std.range.put(output, [0, 0, 0][0 .. padding]);
    return output;
}

ref Output put(Array, Output)(ref Output output, in Array data)
    if (isOutputRange!(Output, ubyte) && isStaticArray!Array)
{
    foreach (const ref elem; data)
    {
        output.put(elem);
    }
    return output;
}

ref Output put(Array, Output)(ref Output output, in Array data)
    if (isOutputRange!(Output, ubyte)
        && isDynamicArray!Array && !is(Array == ubyte[]) && !is(Array == string)
        && __traits(compiles, output.put!(ElementType!Array)(data[0])))
in {
    assert(data.length <= uint.max);
}
body {
    output.put!uint(cast(uint)data.length);
    foreach (const ref elem; data)
    {
        output.put(elem);
    }

    return output;
}

ref Output put(T: ubyte[], Output)(ref Output output, in T data)
    if (isOutputRange!(Output, ubyte))
in {
    assert(data.length <= uint.max);
}
body {
    output.put!uint(cast(uint)data.length);
    std.range.put(output, data);
    if (data.length % 4 > 0)
    {
        immutable pad_length = 4 - (data.length % 4);
        ubyte[] padding = [0, 0, 0];
        std.range.put(output, padding[0 .. pad_length]);
    }

    return output;
}

// FIXME combine with ubyte[]
ref Output put(T: string, Output)(ref Output output, in T data)
    if (isOutputRange!(Output, ubyte))
in {
    assert(data.length <= uint.max);
}
body {
    output.put!uint(cast(uint)data.length);
    std.range.put(output, data);
    if (data.length % 4 > 0)
    {
        immutable pad_length = 4 - (data.length % 4);
        ubyte[] padding = [0, 0, 0];
        std.range.put(output, padding[0 .. pad_length]);
    }
    return output;
}

ref Output put(T, Output)(ref Output output, in T data)
    if (isOutputRange!(Output, ubyte)
        && isAggregateType!T && !hasIndirections!T)
{
    foreach (elem; data.tupleof)
    {
        output.put(elem);
    }
    return output;
}

unittest
{
    ubyte[] serializer;

    assert(__traits(compiles, serializer.put!char(2)) == false);
    assert(__traits(compiles, serializer.put!dchar(2)) == false);
    assert(__traits(compiles, serializer.put!wchar(2)) == false);

    assert(__traits(compiles, serializer.put!byte(2)) == false);
    assert(__traits(compiles, serializer.put!ubyte(2)) == false);
    assert(__traits(compiles, serializer.put!short(2)) == false);
    assert(__traits(compiles, serializer.put!ushort(2)) == false);

    assert(__traits(compiles, serializer.put!int(2)) == true);
    assert(__traits(compiles, serializer.put!uint(2)) == true);
    assert(__traits(compiles, serializer.put!long(2)) == true);
    assert(__traits(compiles, serializer.put!ulong(2)) == true);

    assert(__traits(compiles, serializer.put!bool(true)) == true);

    assert(__traits(compiles, serializer.put!float(1.0)) == true);
    assert(__traits(compiles, serializer.put!double(1.0)) == true);

    assert(__traits(compiles, serializer.put!(ubyte[])([])) == true);
    assert(__traits(compiles, serializer.put!(string)("")) == true);

    assert(__traits(compiles, serializer.put!(short[])([])) == false);
    assert(__traits(compiles, serializer.put!(ushort[])([])) == false);

    assert(__traits(compiles, serializer.put!(short[2])([1, 2])) == false);

    assert(__traits(compiles, serializer.put!(int[2])([1, 2])) == true);
    assert(__traits(compiles, serializer.put!(uint[2])([1, 2])) == true);
    assert(__traits(compiles, serializer.put!(long[2])([1, 2])) == true);
    assert(__traits(compiles, serializer.put!(ulong[2])([1, 2])) == true);
    // Commented out pending std.bitmanip.EndianSwap stuff
    // From std.bitmanip.d:2210
    // private union EndianSwapper(T)
    //     if(canSwapEndianness!T)
    // {
    //     Unqual!T value;
    //     ubyte[T.sizeof] array;
    //
    //     static if(is(FloatingPointTypeOf!T == float))
    //         uint  intValue;
    //     else static if(is(FloatingPointTypeOf!T == double))
    //         ulong intValue;
    //
    // }
    // The static ifs fail because FloatingPointTypeOf!(const(float)) == const(float), not float
    // assert(__traits(compiles, serializer.put!(float[2])([1, 2])) == true);
    // assert(__traits(compiles, serializer.put!(double[2])([1, 2])) == true);
    assert(__traits(compiles, serializer.put!(bool[2])([true, false])) == true);
}

unittest
{
    ubyte[] outBuffer = new ubyte[4];
    ubyte[] movingBuffer = outBuffer[];

    movingBuffer.put!int(4);
    assert(outBuffer == [0, 0, 0, 4]);
}

unittest
{
    ubyte[] outBuffer = new ubyte[4];
    ubyte[] movingBuffer = outBuffer[];

    movingBuffer.put!bool(true);
    assert(outBuffer == [0, 0, 0, 1]);
}

unittest
{
    ubyte[] outBuffer = new ubyte[8];
    ubyte[] movingBuffer = outBuffer[];

    movingBuffer.put!long(4);
    assert(outBuffer == [0, 0, 0, 0, 0, 0, 0, 4]);
}

unittest
{
    ubyte[] outBuffer = new ubyte[8];
    ubyte[] movingBuffer = outBuffer[];

    ubyte[] data = [1, 2, 3, 4];
    movingBuffer.put(data);
    assert(outBuffer == [0, 0, 0, 4, 1, 2, 3, 4]);
}
unittest
{
    ubyte[] outBuffer = new ubyte[8];
    ubyte[] movingBuffer = outBuffer[];

    ubyte[] data = [1, 2, 3];
    movingBuffer.put(data);
    assert(outBuffer == [0, 0, 0, 3, 1, 2, 3, 0]);
}

unittest
{
    ubyte[] outBuffer = new ubyte[12];
    ubyte[] movingBuffer = outBuffer[];

    string data = "hello";
    movingBuffer.put(data);
    assert(outBuffer == [0, 0, 0, 5, 'h', 'e', 'l', 'l', 'o', 0, 0, 0]);
}

unittest
{
    ubyte[] outBuffer = new ubyte[8];
    ubyte[] movingBuffer = outBuffer[];

    int[2] data = [1, 2];
    movingBuffer.put(data);
    assert(outBuffer == [0, 0, 0, 1, 0, 0, 0, 2]);
}

unittest
{
    ubyte[] outBuffer = new ubyte[8];
    ubyte[] movingBuffer = outBuffer[];

    struct AB
    {
        int a;
        int b;
    }

    AB ab = {1, 2};
    movingBuffer.put(ab);
    assert(outBuffer == [0, 0, 0, 1, 0, 0, 0, 2]);
}

unittest
{
    ubyte[] outBuffer = new ubyte[8];
    ubyte[] movingBuffer = outBuffer[];

    movingBuffer.put!int(4).put!int(5);
    assert(outBuffer == [0, 0, 0, 4, 0, 0, 0, 5]);
}

class EndOfInput : Exception
{
    this(string file = __FILE__, size_t line = __LINE__)
    {
        super("Reached end of input while extracting data.", file, line);
    }
}

class NotABool : Exception
{
    this(int intVal, string file = __FILE__, size_t line = __LINE__)
    {
        import std.conv : to;
        super("Tried to decode into a bool, but " ~ std.conv.to!string(intVal) ~ " is not a valid XDR bool.", file, line);
    }
}

// Uses popFrontN, so it may read the end of input without
// doing anything useful with it
T get(T, Input)(ref Input input)
    if ((isInputRange!Input && is(ElementType!Input == ubyte))
        && (T.sizeof % 4 == 0 && (isIntegral!T || isFloatingPoint!T)))
{
    ubyte[T.sizeof] buffer;
    ubyte[] remaining = copy(input.take(T.sizeof), buffer[]);
    if (remaining.length != 0)
    {
        throw new EndOfInput();
    }
    // Only need to pop front here if the input.take() does not.
    // For ubyte[], take does not popFront, but maybe for InputRanges
    // that are not sliceable it does?
    input.popFrontExactly(T.sizeof);
    return bigEndianToNative!T(buffer);
}

bool get(T: bool, Input)(ref Input input)
    if (isInputRange!Input && is(ElementType!Input == ubyte))
{
    immutable intVal = input.get!int();
    if (intVal == 0)
    {
        return false;
    }
    else if (intVal == 1)
    {
        return true;
    }
    else
    {
        throw new NotABool(intVal);
    }
}

auto get(T, Input)(ref Input input)
    if (isInputRange!Input && is(ElementType!Input == ubyte)
        && is(T == ubyte[length], ulong length)
           && isStaticArray!T)
{
    static if (T.length % 4 != 0)
    {
        enum pad_length = 4 - (T.length % 4);
    }
    else
    {
        enum pad_length = 0;
    }

    auto result = input.take(T.length);
    input.popFrontExactly(T.length + pad_length);
    return result;
}

Array get(Array, Input)(ref Input input)
    if (isInputRange!Input && is(ElementType!Input == ubyte)
        && is(Array == Element[length], Element, ulong length)
            && !is(ElementType!Array == ubyte)
            && isStaticArray!Array)
{
    alias Element = ElementType!Array;
    enum length = Array.length;
    static if (Element.sizeof % 4 == 0)
    {
        enum elementSize = Element.sizeof;
    }
    else
    {
        enum elementSize = Element.sizeof + 4 - (Element.sizeof % 4);
    }

    Array result;
    // FIXME check on whether I need to pop front afterwards
    copy(input.take(elementSize * length).chunks(elementSize).map!((chunk)=> chunk.get!Element()), result[]);
    input.popFrontExactly(elementSize * length);
    return result;
}

auto get(Array, Input)(ref Input input)
    if (isInputRange!Input && is(ElementType!Input == ubyte)
        && isDynamicArray!Array && !is(Array == ubyte[]) && !is(Array == string))
{
    alias Element = ElementType!Array;

    uint length = input.get!uint();
    static if (Element.sizeof % 4 == 0)
    {
        enum elementSize = Element.sizeof;
    }
    else
    {
        enum elementSize = Element.sizeof + 4 - (Element.sizeof % 4);
    }

    Array result = new Element[length];
    // FIXME check on whether I need to pop front afterwards
    copy(input.take(elementSize * length).chunks(elementSize).map!((chunk)=> chunk.get!Element()), result[]);
    input.popFrontExactly(elementSize * length);
    return result;
}

auto get(Array, Input)(ref Input input)
    if (isInputRange!Input && is(ElementType!Input == ubyte)
        && isDynamicArray!Array && (is(Array == ubyte[]) || is(Array == string)))
{
    uint length = input.get!uint();
    auto result = input.take(length);

    input.popFrontExactly(length);
    if (length % 4 > 0)
    {
        input.popFrontExactly(4 - (length % 4));
    }
    return result;
}

T get(T, Input)(ref Input input)
    if (isInputRange!Input && is(ElementType!Input == ubyte)
        && isAggregateType!T && !hasIndirections!T)
{
    T result;
    foreach (ref elem; result.tupleof)
    {
        elem = input.get!(typeof(elem));
    }

    return result;
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 4];

    assert(inBuffer.get!int() == 4);
}
unittest
{
    ubyte[] inBuffer = [0, 0, 0, 4, 0, 0, 0, 12];

    assert(inBuffer.get!int() == 4);
    assert(inBuffer.get!int() == 12);

    assertThrown!EndOfInput(inBuffer.get!int());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2];

    assert(inBuffer.get!bool() == true);
    assert(inBuffer.get!bool() == false);
    assertThrown!NotABool(inBuffer.get!bool());
    assertThrown!EndOfInput(inBuffer.get!bool());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 0, 0, 0, 0, 4];

    assert(inBuffer.get!long() == 4);
    assertThrown!EndOfInput(inBuffer.get!long());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 4, 1, 2, 3, 4];

    assert(inBuffer.get!(ubyte[])() == [1, 2, 3, 4]);
    assertThrown!EndOfInput(inBuffer.get!(ubyte[])());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 3, 1, 2, 3, 0];

    assert(inBuffer.get!(ubyte[])() == [1, 2, 3]);
    assertThrown!EndOfInput(inBuffer.get!int());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 5, 'h', 'e', 'l', 'l', 'o', 0, 0, 0];

    assert(inBuffer.get!string() == "hello");
    assertThrown!EndOfInput(inBuffer.get!int());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 1, 0, 0, 0, 2];

    assert(inBuffer.get!(int[2])() == [1, 2]);
    assertThrown!EndOfInput(inBuffer.get!int());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 2];

    assert(inBuffer.get!(int[])() == [1, 2]);
    assertThrown!EndOfInput(inBuffer.get!int());
}

unittest
{
    ubyte[] inBuffer = [1, 2, 0, 0];

    assert(inBuffer.get!(ubyte[2])() == [1, 2]);
    assertThrown!EndOfInput(inBuffer.get!int());
}

unittest
{
    ubyte[] inBuffer = [1, 2, 3, 4];

    assert(inBuffer.get!(ubyte[4])() == [1, 2, 3, 4]);
    assertThrown!EndOfInput(inBuffer.get!int());
}

unittest
{
    ubyte[] inBuffer = [0, 0, 0, 1, 0, 0, 0, 2];

    struct AB
    {
        int a;
        int b;
    }

    AB ab = {1, 2};
    assert(inBuffer.get!AB() == ab);
    assertThrown!EndOfInput(inBuffer.get!int());
}
