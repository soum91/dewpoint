import Foundation

/// Decodes Govee thermo-hygrometer BLE advertisements.
/// Formats follow the open-source govee-ble parser used by Home Assistant (MIT).
struct GoveeAdvert: Equatable {
    let model: String
    let tempC: Double
    let humidity: Double
    let battery: Int
}

enum GoveeParser {
    /// Pulls a model number like "H5102" out of names such as "GVH5102_9A4C" or "Govee_H5075_1234".
    static func model(from name: String) -> String? {
        guard let r = name.range(of: #"H5\d{3}"#, options: .regularExpression) else {
            if let r2 = name.range(of: #"GV5\d{3}"#, options: .regularExpression) {
                return "H" + name[r2].dropFirst(2)
            }
            return nil
        }
        return String(name[r])
    }

    static func looksLikeGovee(name: String) -> Bool {
        let n = name.uppercased()
        return n.hasPrefix("GV") || n.hasPrefix("GOVEE") || n.hasPrefix("IHOMENT") || n.contains("H5")
    }

    /// Three-byte packed temp/humidity used by H5072/H5075/H510x/H5174/H5177.
    static func decodePacked(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> (Double, Double)? {
        let base = (Int(a) << 16) | (Int(b) << 8) | Int(c)
        if base == 0xFFFFFF { return nil }
        let negative = (base & 0x800000) != 0
        let v = base & 0x7FFFFF
        var t = Double(v / 1000) / 10.0
        if negative { t = -t }
        let h = Double(v % 1000) / 10.0
        return (t, h)
    }

    /// `manufacturerData` is CoreBluetooth's raw value: 2-byte little-endian company ID followed by payload.
    static func parse(name rawName: String?, manufacturerData: Data?) -> GoveeAdvert? {
        guard let md = manufacturerData, md.count >= 3 else { return nil }
        let bytes = [UInt8](md)
        let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        if company == 0x004C { return nil } // Apple iBeacon frames, never Govee data
        let p = Array(bytes[2...])
        let name = rawName ?? ""
        let hinted = model(from: name)
        let isGoveeName = name.hasPrefix("GV") || name.hasPrefix("Govee") || name.contains("H5")

        var result: GoveeAdvert?

        let fiveO75Family: Set<String> = ["H5072", "H5075", "H5129"]
        let fiveOneFamily: Set<String> = ["H5100", "H5101", "H5102", "H5103", "H5104", "H5105",
                                          "H5108", "H5110", "H5174", "H5177", "H5179"]

        if p.count == 6, (hinted.map { fiveO75Family.contains($0) } ?? false) || (company == 0xEC88 && isGoveeName) {
            // H5072 / H5075: payload[1...3] packed, payload[4] battery
            if let (t, h) = decodePacked(p[1], p[2], p[3]), p[4] & 0x80 == 0 {
                result = GoveeAdvert(model: hinted ?? "H5075", tempC: t, humidity: h, battery: Int(p[4] & 0x7F))
            }
        } else if p.count == 6, (hinted.map { fiveOneFamily.contains($0) } ?? false) || (company == 0x0001 && isGoveeName) {
            // H5101 / H5102 / H5104 / H5174 / H5177: payload[2...4] packed, payload[5] battery
            if let (t, h) = decodePacked(p[2], p[3], p[4]), p[5] & 0x80 == 0 {
                result = GoveeAdvert(model: hinted ?? "H5102", tempC: t, humidity: h, battery: Int(p[5] & 0x7F))
            }
        } else if p.count == 7, hinted == "H5074" || (company == 0xEC88 && isGoveeName) {
            let t = Double(Int16(bitPattern: UInt16(p[1]) | UInt16(p[2]) << 8)) / 100
            let h = Double(UInt16(p[3]) | UInt16(p[4]) << 8) / 100
            result = GoveeAdvert(model: "H5074", tempC: t, humidity: h, battery: Int(p[5]))
        } else if p.count == 9, hinted == "H5179" || (company == 0x8801 && isGoveeName) {
            let t = Double(Int16(bitPattern: UInt16(p[4]) | UInt16(p[5]) << 8)) / 100
            let h = Double(UInt16(p[6]) | UInt16(p[7]) << 8) / 100
            result = GoveeAdvert(model: "H5179", tempC: t, humidity: h, battery: Int(p[8]))
        }

        guard let r = result, (-40...100).contains(r.tempC), (0...100).contains(r.humidity) else { return nil }
        return r
    }
}
