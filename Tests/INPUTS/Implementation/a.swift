/*a.swift*/
protocol /*Protocol*/Protocol {
    static var /*ProtocolStaticVar*/staticVar: Int { get }
    static func /*ProtocolStaticFunction*/staticFunction()
    var /*ProtocolVariable*/variable: Int { get }
    func /*ProtocolFunction*/function()
}
class /*Class*/Class {
    class var /*ClassClassVar*/classVar: Int { 123 }
    class func /*ClassClassFunction*/classFunction() {}
    var /*ClassVariable*/variable: Int { 123 }
    func /*ClassFunction*/function() {}
}


class /*Sepulcidae*/Sepulcidae {}
    class /*Parapamphiliinae*/Parapamphiliinae: /*ParapamphiliinaeConformance*/Sepulcidae {}
        class Micramphilius: /*MicramphiliusConformance*/Parapamphiliinae {}
        class Pamparaphilius: /*PamparaphiliusConformance*/Parapamphiliinae {}
    class /*Xyelulinae*/Xyelulinae: /*XyelulinaeConformance*/Sepulcidae {}
        class Xyelula: /*XyelulaConformance*/Xyelulinae {}
    class /*Trematothoracinae*/Trematothoracinae: /*TrematothoracinaeConformance*/Sepulcidae {}
    

protocol /*Prozaiczne*/Prozaiczne {}
protocol /*Sepulkowate*/Sepulkowate {
    func /*rozpocznijSepulenie*/rozpocznijSepulenie()
}

class Pćma {}
class /*Murkwia*/Murkwia: /*MurkwiaConformance1*/Sepulkowate, /*MurkwiaConformance2*/Prozaiczne {
    func /*MurkwiaFunc*/rozpocznijSepulenie() {}
}
class /*Sepulka*/Sepulka: /*SepulkaConformance1*/Prozaiczne, /*SepulkaConformance2*/Sepulkowate {
    var size: Double { 10 }
    var /*SepulkaVar*/patroka: String { "puszysta" }
    func /*SepulkaFunc*/rozpocznijSepulenie() {}
}
class SepulkaDwuuszna: /*SepulkaDwuusznaConformance*/Sepulka {
    override var /*SepulkaDwuusznaVar*/patroka: String { "glazurowana" }
}
class SepulkaPrzechylna: /*SepulkaPrzechylnaConformance*/Sepulka {
    override var /*SepulkaPrzechylnaVar*/patroka: String { "piaskowana" }
}
class PćmaŁagodna: Pćma {
    func /*PćmaŁagodnaFunc*/rozpocznijSepulenie() { }
}
extension PćmaŁagodna: /*PćmaŁagodnaConformance*/Sepulkowate {}

class PćmaZwyczajna: Pćma {}
extension PćmaZwyczajna: /*PćmaZwyczajnaConformance*/Sepulkowate {
    func /*PćmaZwyczajnaFunc*/rozpocznijSepulenie() { }
}
