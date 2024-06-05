//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKTestSupport
import XCTest

private let libAlibBPackageManifest = """
  let package = Package(
    name: "MyLibrary",
    targets: [
     .target(name: "LibA"),
     .target(name: "LibB", dependencies: ["LibA"]),
    ]
  )
  """

private let libAlibBCxxInteropPackageManifest = """
  let package = Package(
    name: "MyLibrary",
    targets: [
    .target(name: "LibA"),
    .target(name: "LibB", dependencies: ["LibA"], swiftSettings: [.interoperabilityMode(.Cxx)]),
    ]
  )
  """

final class CrossLanguageRenameTests: XCTestCase {
  func testZeroArgCFunction() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        void 1️⃣cFunc();
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void 2️⃣cFunc() {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          3️⃣cFunc()
        }
        """,
      ],
      headerFileLanguage: .c,
      newName: "dFunc",
      expectedPrepareRenamePlaceholder: "cFunc",
      expected: [
        "LibA/include/LibA.h": """
        void dFunc();
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void dFunc() {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          dFunc()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testMultiArgCFunction() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        void 1️⃣cFunc(int x, int y);
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void 2️⃣cFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          3️⃣cFunc(1, 2)
        }
        """,
      ],
      headerFileLanguage: .c,
      newName: "dFunc",
      expectedPrepareRenamePlaceholder: "cFunc",
      expected: [
        "LibA/include/LibA.h": """
        void dFunc(int x, int y);
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void dFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          dFunc(1, 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testCFunctionWithSwiftNameAnnotation() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        void 1️⃣cFunc(int x, int y) __attribute__((swift_name("cFunc(x:y:)")));
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void 2️⃣cFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          3️⃣cFunc(x: 1, y: 2)
        }
        """,
      ],
      headerFileLanguage: .c,
      newName: "dFunc",
      expectedPrepareRenamePlaceholder: "cFunc",
      expected: [
        "LibA/include/LibA.h": """
        void dFunc(int x, int y) __attribute__((swift_name("cFunc(x:y:)")));
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void dFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          cFunc(x: 1, y: 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testZeroArgObjCSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performAction {
          return [self 2️⃣performAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣performAction()
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction",
      expectedPrepareRenamePlaceholder: "performAction",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction {
          return [self performNewAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.performNewAction()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testZeroArgObjCClassSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)1️⃣performAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        + (int)performAction {
          return [Foo 2️⃣performAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.3️⃣performAction()
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction",
      expectedPrepareRenamePlaceholder: "performAction",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)performNewAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        + (int)performNewAction {
          return [Foo performNewAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.performNewAction()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testOneArgObjCSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction:(int)action;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)2️⃣performAction:(int)action {
          return [self performAction:action];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣performAction(1)
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction:",
      expectedPrepareRenamePlaceholder: "performAction:",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction:(int)action;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction:(int)action {
          return [self performNewAction:action];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.performNewAction(1)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testMultiArgObjCSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction:(int)action with:(int)value;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)2️⃣performAction:(int)action with:(int)value {
          return [self performAction:action with:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣performAction(1, with: 2)
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction:by:",
      expectedPrepareRenamePlaceholder: "performAction:with:",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction:(int)action by:(int)value;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction:(int)action by:(int)value {
          return [self performNewAction:action by:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.performNewAction(1, by: 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testObjCSelectorWithSwiftNameAnnotation() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction:(int)action withValue:(int)value __attribute__((swift_name("perform(action:with:)")));
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)2️⃣performAction:(int)action withValue:(int)value {
          return [self performAction:action withValue:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣perform(action: 1, with: 2)
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction:by:",
      expectedPrepareRenamePlaceholder: "performAction:withValue:",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction:(int)action by:(int)value __attribute__((swift_name("perform(action:with:)")));
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction:(int)action by:(int)value {
          return [self performNewAction:action by:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.perform(action: 1, with: 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testObjCClass() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface 1️⃣Foo
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation 2️⃣Foo
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: 3️⃣Foo) {
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "Bar",
      expectedPrepareRenamePlaceholder: "Foo",
      expected: [
        "LibA/include/LibA.h": """
        @interface Bar
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Bar
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Bar) {
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testObjCClassWithSwiftNameAnnotation() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        __attribute__((swift_name("Foo")))
        @interface 1️⃣AHFoo
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation 2️⃣AHFoo
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: 3️⃣Foo) {
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "AHBar",
      expectedPrepareRenamePlaceholder: "AHFoo",
      expected: [
        "LibA/include/LibA.h": """
        __attribute__((swift_name("Foo")))
        @interface AHBar
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation AHBar
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testCppMethod() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          void 1️⃣doStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::2️⃣doStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣doStuff()
        }
        """,
      ],
      headerFileLanguage: .cpp,
      newName: "doCoolStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          void doCoolStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::doCoolStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.doCoolStuff()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"], swiftSettings: [.unsafeFlags(["-cxx-interoperability-mode=default"])]),
          ]
        )
        """
    )
  }

  func testCppMethodWithSwiftName() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          void 1️⃣doStuff(int x) const __attribute__((swift_name("do(stuff:)")));
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::2️⃣doStuff(int x) const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣do(stuff: 1)
        }
        """,
      ],
      headerFileLanguage: .cpp,
      newName: "doCoolStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          void doCoolStuff(int x) const __attribute__((swift_name("do(stuff:)")));
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::doCoolStuff(int x) const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.do(stuff: 1)
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"], swiftSettings: [.unsafeFlags(["-cxx-interoperability-mode=default"])]),
          ]
        )
        """
    )
  }

  func testCppMethodInObjCpp() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          void 1️⃣doStuff() const;
        };
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        void Foo::2️⃣doStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣doStuff()
        }
        """,
      ],
      headerFileLanguage: .objective_cpp,
      newName: "doCoolStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          void doCoolStuff() const;
        };
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        void Foo::doCoolStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.doCoolStuff()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"], swiftSettings: [.unsafeFlags(["-cxx-interoperability-mode=default"])]),
          ]
        )
        """
    )
  }

  func testZeroArgObjCClassSelectorInObjCpp() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)1️⃣performAction;
        @end
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        @implementation Foo
        + (int)performAction {
          return [Foo 2️⃣performAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.3️⃣performAction()
        }
        """,
      ],
      headerFileLanguage: .objective_cpp,
      newName: "performNewAction",
      expectedPrepareRenamePlaceholder: "performAction",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)performNewAction;
        @end
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        @implementation Foo
        + (int)performNewAction {
          return [Foo performNewAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.performNewAction()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testRenameCxxClassExposedToSwift() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct 1️⃣Foo {};
        """,
        "LibA/LibA.cpp": "",
        "LibB/LibB.swift": """
        import LibA

        func test(foo: 2️⃣Foo) {}
        """,
      ],
      headerFileLanguage: .cpp,
      newName: "Bar",
      expectedPrepareRenamePlaceholder: "Foo",
      expected: [
        "LibA/include/LibA.h": """
        struct Bar {};
        """,
        "LibA/LibA.cpp": "",
        "LibB/LibB.swift": """
        import LibA

        func test(foo: Bar) {}
        """,
      ],
      manifest: libAlibBCxxInteropPackageManifest
    )
  }

  func testRenameCxxMethodExposedToSwift() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          int 1️⃣doStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        int Foo::2️⃣doStuff() const {
          return 42;
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        func test(foo: Foo) {
          foo.3️⃣doStuff()
        }
        """,
      ],
      headerFileLanguage: .cpp,
      newName: "doNewStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          int doNewStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        int Foo::doNewStuff() const {
          return 42;
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        func test(foo: Foo) {
          foo.doNewStuff()
        }
        """,
      ],
      manifest: libAlibBCxxInteropPackageManifest
    )
  }

  func testRenameSwiftMethodExposedToSwift() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          int 1️⃣doStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        int Foo::2️⃣doStuff() const {
          return 42;
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        func test(foo: Foo) {
          foo.3️⃣doStuff()
        }
        """,
      ],
      headerFileLanguage: .cpp,
      newName: "doNewStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          int doNewStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        int Foo::doNewStuff() const {
          return 42;
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        func test(foo: Foo) {
          foo.doNewStuff()
        }
        """,
      ],
      manifest: libAlibBCxxInteropPackageManifest
    )
  }
}
