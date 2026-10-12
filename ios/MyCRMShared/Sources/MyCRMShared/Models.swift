import Foundation

public struct LocationSamplePayload: Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracyM: Double?
    public var altitudeM: Double?
    public var speedMps: Double?
    public var recordedAt: String
    public var source: String
    public var deviceId: String?

    public init(
        latitude: Double,
        longitude: Double,
        accuracyM: Double? = nil,
        altitudeM: Double? = nil,
        speedMps: Double? = nil,
        recordedAt: Date = Date(),
        source: String = "ios",
        deviceId: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyM = accuracyM
        self.altitudeM = altitudeM
        self.speedMps = speedMps
        self.recordedAt = ISO8601DateFormatter.mycrm.string(from: recordedAt)
        self.source = source
        self.deviceId = deviceId
    }

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case accuracyM = "accuracy_m"
        case altitudeM = "altitude_m"
        case speedMps = "speed_mps"
        case recordedAt = "recorded_at"
        case source
        case deviceId = "device_id"
    }
}

public struct LocationUploadResponse: Codable, Sendable {
    public var id: Int
    public var messagesLocated: Int

    enum CodingKeys: String, CodingKey {
        case id
        case messagesLocated = "messages_located"
    }
}

public struct CRMMessage: Codable, Identifiable, Sendable {
    public var id: Int
    public var body: String?
    public var direction: String
    public var sentAt: String
    public var latitude: Double?
    public var longitude: Double?
    public var accuracyM: Double?
    public var locatedAt: String?
    public var contactName: String?

    enum CodingKeys: String, CodingKey {
        case id, body, direction
        case sentAt = "sent_at"
        case latitude, longitude
        case accuracyM = "accuracy_m"
        case locatedAt = "located_at"
        case contactName = "contact_name"
    }
}

extension ISO8601DateFormatter {
    public static let mycrm: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
