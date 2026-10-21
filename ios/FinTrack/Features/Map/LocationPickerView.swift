import CoreLocation
import MapKit
import SwiftUI

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var locationName: String?
    @StateObject private var locationManager = LocationManager()
    @State private var position: MapCameraPosition
    @State private var geocoder = CLGeocoder()

    init(coordinate: Binding<CLLocationCoordinate2D?>, locationName: Binding<String?>) {
        _coordinate = coordinate
        _locationName = locationName
        let startingPoint = coordinate.wrappedValue ?? CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: startingPoint,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )))
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    if let coordinate {
                        Marker("Transaction location", coordinate: coordinate)
                            .tint(FinTrackStyle.purple)
                    }
                }
                .mapStyle(.standard)
                .onTapGesture { point in
                    guard let newCoordinate = proxy.convert(point, from: .local) else { return }
                    setLocation(newCoordinate)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let locationName {
                        Text(locationName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap the map to choose a place")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Use Current Location", systemImage: "location.fill") {
                        locationManager.requestCurrentLocation()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    if let errorMessage = locationManager.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    if coordinate != nil {
                        Button("Remove Location", role: .destructive) {
                            coordinate = nil
                            locationName = nil
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Transaction Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onReceive(locationManager.$location.compactMap { $0 }) { location in
                setLocation(location.coordinate)
            }
        }
    }

    private func setLocation(_ newCoordinate: CLLocationCoordinate2D) {
        coordinate = newCoordinate
        position = .region(MKCoordinateRegion(
            center: newCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
        geocoder.cancelGeocode()
        let location = CLLocation(latitude: newCoordinate.latitude, longitude: newCoordinate.longitude)
        Task {
            guard let places = try? await geocoder.reverseGeocodeLocation(location),
                  let place = places.first else { return }
            let parts = [place.name, place.locality, place.administrativeArea]
                .compactMap { $0 }
            locationName = parts.uniqued().joined(separator: ", ")
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var result: [Element] = []
        for value in self where !result.contains(value) { result.append(value) }
        return result
    }
}
