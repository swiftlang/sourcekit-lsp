/*a.swift*/
protocol /*P*/P {}
protocol /*X*/X {}

class /*A*/A {}
class /*B*/B: A, P {}
class /*C*/C: B {}
class /*D*/D: A {}

struct /*S*/S: P {}
enum /*E*/E: P {}

extension /*extS:X*/S: X {}
extension /*extS*/S {
  func x() {}
}

let a: /*typeA*/A = /*initA*/A()
let s: /*typeS*/S = /*initS*/S()
