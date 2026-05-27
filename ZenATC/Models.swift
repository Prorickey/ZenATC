//
//  Models.swift
//  ZenATC
//

import Foundation

struct Airport: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let city: String
    let atcFilename: String
}

extension Airport {
    static let all: [Airport] = [
        Airport(code: "ATL", name: "Hartsfield-Jackson Atlanta Intl", city: "Atlanta",     atcFilename: "atc_atl"),
        Airport(code: "LAX", name: "Los Angeles Intl",                 city: "Los Angeles", atcFilename: "atc_lax"),
        Airport(code: "ORD", name: "O'Hare Intl",                      city: "Chicago",     atcFilename: "atc_ord"),
        Airport(code: "DFW", name: "Dallas/Fort Worth Intl",           city: "Dallas",      atcFilename: "atc_dfw"),
        Airport(code: "JFK", name: "John F. Kennedy Intl",             city: "New York",    atcFilename: "atc_jfk"),
    ]
}

struct LofiTrack: Identifiable {
    let id = UUID()
    let name: String
    let filename: String
}

extension LofiTrack {
    static let all: [LofiTrack] = [
        LofiTrack(name: "Late Night Study", filename: "lofi_late_night"),
        LofiTrack(name: "Rainy Day",        filename: "lofi_rainy_day"),
        LofiTrack(name: "Work Flow",        filename: "lofi_work_flow"),
        LofiTrack(name: "Energy Boost",     filename: "lofi_energy"),
    ]
}
