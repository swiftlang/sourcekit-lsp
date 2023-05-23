public func libFunc() async {
  let a: /*lib.string*/String = "test"
  let i: /*lib.integer*/Int = 2
  await /*lib.withTaskGroup*/withTaskGroup(of: Void.self) { group in
    group.addTask {
      print(a)
      print(i)
    }
  }
}