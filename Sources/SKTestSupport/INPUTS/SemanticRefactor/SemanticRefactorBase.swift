func foo() -> String {
  /*sr:extractStart*/var a = "/*sr:string*/"
  return a/*sr:extractEnd*/
}
/*sr:foo*/

func localRename() {
  var /*sr:local*/local = 1
  _ = local
}
