public struct FancyLib {
  public func sayHello() {}

  public init() {}
}

func topLevelFunction() {
  FancyLib() . /*FancyLib.sayHello:call*/ sayHello()
}
