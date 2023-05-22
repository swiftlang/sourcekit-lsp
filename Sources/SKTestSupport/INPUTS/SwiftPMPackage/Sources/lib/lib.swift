public struct Lib {
  let a: /*Lib.a.string*/String

  public func /*Lib.foo:def*/foo() {}

  public init() {
    self.a = "lib"
  }
}

func topLevelFunction() {
  /*Lib.topLevelFunction:body*/
}