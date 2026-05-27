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
    let isPro: Bool
}

extension Airport {
    static let all: [Airport] = [
        // Free airports
        Airport(code: "JFK", name: "John F. Kennedy Intl",            city: "New York Kennedy", atcFilename: "atc_jfk", isPro: false),
        Airport(code: "SFO", name: "San Francisco Intl",              city: "San Francisco",    atcFilename: "atc_sfo", isPro: false),
        Airport(code: "MIA", name: "Miami Intl",                      city: "Miami",            atcFilename: "atc_mia", isPro: false),
        Airport(code: "ORD", name: "O'Hare Intl",                     city: "Chicago O'Hare",   atcFilename: "atc_ord", isPro: false),
        // Pro airports
        Airport(code: "LAX", name: "Los Angeles Intl",                city: "Los Angeles",      atcFilename: "atc_lax", isPro: true),
        Airport(code: "LAS", name: "Harry Reid Intl",                 city: "Las Vegas",        atcFilename: "atc_las", isPro: true),
        Airport(code: "EWR", name: "Newark Liberty Intl",             city: "Newark",           atcFilename: "atc_ewr", isPro: true),
        Airport(code: "SEA", name: "Seattle-Tacoma Intl",             city: "Seattle",          atcFilename: "atc_sea", isPro: true),
        Airport(code: "DFW", name: "Dallas/Fort Worth Intl",          city: "Dallas",           atcFilename: "atc_dfw", isPro: true),
        Airport(code: "ATL", name: "Hartsfield-Jackson Atlanta Intl", city: "Atlanta",          atcFilename: "atc_atl", isPro: true),
        Airport(code: "SAV", name: "Savannah/Hilton Head Intl",       city: "Savannah",         atcFilename: "atc_sav", isPro: true),
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
