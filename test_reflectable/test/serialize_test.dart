// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test_reflectable.test.serialize_test;

import "package:unittest/unittest.dart";
import "package:test_reflectable/serialize.dart";

// By annotating with [Serializable] we indicate that [A] can be serialized
// and reconstructed.
@Serializable()
class A {
  var a;
  var b;
  // The default constructor will be used for creating new instances when
  // deserializing.
  A();

  // This is just a convenience constructor for making the test data.
  A.fromValues(this.a, this.b);

  toString() => "A(a = $a, b = $b)";

  /// Special case lists.
  _equalsHandlingLists(dynamic x, dynamic y) {
    if (x is List) {
      if (y is! List) return false;
      for (int i = 0; i < x.length; i++) {
        if (!_equalsHandlingLists(x[i], y[i])) return false;
      }
      return true;
    }
    return x == y;
  }

  // The == operator is defined for testing if the reconstructed object is the
  // same as the original.
  bool operator ==(other) {
    return _equalsHandlingLists(a, other.a) && _equalsHandlingLists(b, other.b);
  }
}

@Serializable()
class B extends A {
  var c;
  B();

  B.fromValues(a, b, this.c) : super.fromValues(a, b);

  // The == operator is defined for testing if the reconstructed object is the
  // same as the original.
  // This is defined for easier testing.
  bool operator ==(other) {
    return _equalsHandlingLists(a, other.a) &&
        _equalsHandlingLists(b, other.b) &&
        _equalsHandlingLists(c, other.c);
  }
}

main() {
  Serializer serializer = new Serializer();
  test("Round trip test", () {
    var input = new A.fromValues(
        "one", new A.fromValues(2, [3, new A.fromValues(4, 5)]));
    var out = serializer.serialize(input);
    // Assert that the output of the serialization is equals to
    // the expected map:
    expect(out, {
      "type": "test_reflectable.test.serialize_test.A",
      "fields": {
        "a": {"type": "String", "val": "one"},
        "b": {
          "type": "test_reflectable.test.serialize_test.A",
          "fields": {
            "a": {"type": "num", "val": 2},
            "b": {
              "type": "List",
              "val": [
                {"type": "num", "val": 3},
                {
                  "type": "test_reflectable.test.serialize_test.A",
                  "fields": {
                    "a": {"type": "num", "val": 4},
                    "b": {"type": "num", "val": 5}
                  }
                }
              ]
            }
          }
        }
      }
    });
    // Assert that deserializing the output gives a result that is equal to the
    // original input.
    expect(serializer.deserialize(out), input);
  });
  test("Serialize subtype", () {
    var input = new A.fromValues(1, new B.fromValues(1, 2, 3));
    var output = serializer.serialize(input);
    expect(output, {
      "type": "test_reflectable.test.serialize_test.A",
      "fields": {
        "a": {"type": "num", "val": 1},
        "b": {
          "type": "test_reflectable.test.serialize_test.B",
          "fields": {
            "a": {"type": "num", "val": 1},
            "b": {"type": "num", "val": 2},
            "c": {"type": "num", "val": 3}
          }
        }
      }
    });
    expect(serializer.deserialize(output), input);
  });
}
