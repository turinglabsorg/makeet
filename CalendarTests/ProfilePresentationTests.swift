import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Makeet

@MainActor final class ProfilePresentationTests: XCTestCase {
    func testPhotoNormalizationStripsMetadataAndBoundsDecodedSize() throws {
        let image = try fixtureImage()
        let output = try ProfileImage.normalize(image)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as? Int ?? 999, 320)
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelHeight] as? Int ?? 999, 320)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertLessThan(output.count, 128*1024)
        XCTAssertThrowsError(try ProfileImage.normalize(Data("not an image".utf8)))
    }

    func testProfileCacheAndRenderedPhotoStayWithinTheirAccount() throws {
        let owner = UUID(), other = UUID()
        let directory = try AccountStoreLocation().directory(for: owner)
        let otherDirectory = try AccountStoreLocation().directory(for: other)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: otherDirectory)
        }
        let image = try ProfileImage.normalize(fixtureImage())
        let fixture = AccountProfile(name: "Alex Morgan", image: image, revision: 4)
        try AccountCoding.encoder().encode(fixture).write(to: directory.appendingPathComponent("profile.json"))
        let api = try AccountAPI(storage: EmptyProfileSession())
        let service = try AccountProfileService(userID: owner, api: api)
        let isolated = try AccountProfileService(userID: other, api: api)
        XCTAssertEqual(service.value, fixture)
        XCTAssertNil(isolated.value.image)
        XCTAssertTrue(isolated.value.name.isEmpty)
        let renderer = ImageRenderer(content: ProfileIdentityHeader(profile: service.value, email: "alex@example.invalid")
            .padding(24).frame(width: 390).background(Palette.paper))
        let rendered = try XCTUnwrap(renderer.uiImage)
        let proof = XCTAttachment(image: rendered)
        proof.name = "Private profile with image"; proof.lifetime = .keepAlways
        add(proof)
    }

    private func fixtureImage() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.43, blue: 0.32, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        context.setFillColor(CGColor(red: 0.9, green: 0.77, blue: 0.49, alpha: 1)); context.fillEllipse(in: CGRect(x: 190, y: 110, width: 260, height: 260))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private struct EmptyProfileSession: SessionStorage {
    func load() throws -> StoredSession? { nil }
    func save(_ session: StoredSession) throws {}
    func clear() throws {}
}
