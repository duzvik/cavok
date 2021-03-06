//
//  WeatherModule.swift
//  CAVOK
//
//  Created by Juho Kolehmainen on 08.09.16.
//  Copyright © 2016 Juho Kolehmainen. All rights reserved.
//

import Foundation

class Ceiling: WeatherModule, MapModule {
    required init(delegate: MapDelegate) {
        super.init(delegate: delegate, observationValue: { $0.cloudHeight.value })
    }
}

class Visibility: WeatherModule, MapModule {
    required init(delegate: MapDelegate) {
        super.init(delegate: delegate, observationValue: { $0.visibility.value })
    }
}

final class Temperature: WeatherModule, MapModule {
    required init(delegate: MapDelegate) {
        super.init(delegate: delegate, observationValue: { ($0 as? Metar)?.spreadCeiling() })
    }
}


open class WeatherModule {

    private let delegate: MapDelegate
    
    private let ramp: ColorRamp
    
    private let weatherService = WeatherServer()
    
    private let observationValue: (Observation) -> Int?
    
    private let weatherLayer: WeatherLayer
    
    public init(delegate: MapDelegate, observationValue: @escaping (Observation) -> Int?) {
        self.delegate = delegate
        
        self.observationValue = observationValue
        
        let ramp = ColorRamp(module: type(of: self))
        self.ramp = ramp
        
        let region = WeatherRegion.load()
        
        self.weatherLayer = WeatherLayer(mapView: delegate.mapView, ramp: ramp, observationValue: observationValue, region: region)
        
        if region != nil {
            load(observations: weatherService.observations())
        }
    }
    
    deinit {
        delegate.clearAnnotations(ofType: nil)
        delegate.clearComponents(ofType: ObservationMarker.self)
    }
    
    // MARK: - Region selection
    
    func didTapAt(coord: MaplyCoordinate) {
        if let selection = delegate.findComponent(ofType: RegionSelection.self) as? RegionSelection {
            selection.region.center = coord
            startRegionSelection(at: selection.region)
        }
    }
    
    private func startRegionSelection(at region: WeatherRegion) {
        delegate.setStatus(text: "Select monitored region", color: .black)
        
        let annotation = RegionAnnotationView(region: region,
                                              closed: self.endRegionSelection,
                                              resized: self.showRegionSelection)
        delegate.mapView.addAnnotation(annotation, forPoint: region.center, offset: CGPoint.zero)
        
        showRegionSelection(at: region)
    }
    
    private func showRegionSelection(at region: WeatherRegion) {
        delegate.clearComponents(ofType: RegionSelection.self)
        
        let selection = RegionSelection(region: region)
        if let stickers = delegate.mapView.addStickers([selection], desc: [kMaplyFade: 1.0]) {
            delegate.addComponents(key: selection, value: stickers)
        }
        
        showStations(at: region)
    }
    
    private func showStations(at region: WeatherRegion) {
        delegate.clearComponents(ofType: StationMarker.self)
        weatherService.queryStations(at: region).then { stations -> Void in
            let markers = stations.map { station in StationMarker(station: station) }
            if let key = markers.first, let components = self.delegate.mapView.addScreenMarkers(markers, desc: nil) {
                self.delegate.addComponents(key: key, value: components)
            }
        }.catch { error in
            self.delegate.setStatus(error: error)
        }
    }
    
    private func endRegionSelection(at region: WeatherRegion? = nil) {
        delegate.clearComponents(ofType: StationMarker.self)
        delegate.clearComponents(ofType: RegionSelection.self)
        delegate.clearAnnotations(ofType: RegionAnnotationView.self)
        
        if region?.save() == true {
            weatherLayer.reposition(region: region!)
            
            refreshStations()
        } else {
            load(observations: weatherService.observations())
        }
    }
    
    func configure(open: Bool, userLocation: MaplyCoordinate?) {
        delegate.clearComponents(ofType: ObservationMarker.self)
        self.weatherLayer.clean()
        
        if open {
            let region = WeatherRegion.load() ?? WeatherRegion(center: userLocation ?? delegate.mapView.getPosition(),
                                                               radius: 100)
            startRegionSelection(at: region)
        } else {
            endRegionSelection()
        }
    }
    
    // MARK: - Observations
    
    func refresh() {
        delegate.setStatus(text: "Refreshing observations...", color: .black)
        
        weatherService.refreshObservations()
            .then(execute: load)
            .catch(execute: { error -> Void in
                self.delegate.setStatus(error: error)
            })
    }
    
    private func refreshStations() {
        delegate.setStatus(text: "Reloading stations...", color: .black)
        
        weatherService.refreshStations().then { stations -> Void in
            self.delegate.setStatus(text: "Found \(stations.count) stations...", color: UIColor.black)
            self.refresh()
        }.catch { error -> Void in
            self.delegate.setStatus(error: error)
        }
    }
    
    private func load(observations: Observations) {
        let groups = observations.group()
        
        self.weatherLayer.load(groups: groups)
        self.delegate.loaded(frame: groups.selectedFrame, timeslots: groups.timeslots, legend: ramp.legend())
        self.render(frame: groups.selectedFrame)
    }
    
    func render(frame: Int?) {
        guard let frame = frame else {
            delegate.setStatus(text: "No data, click to reload.", color: ColorRamp.color(for: .IFR))
            return
        }
        
        delegate.clearAnnotations(ofType: nil)
        delegate.clearComponents(ofType: ObservationMarker.self)
        
        let observations = weatherLayer.go(frame: frame)
        
        let markers = observations.map { obs in
            return ObservationMarker(obs: obs)
        }
        
        if let key = markers.first, let components = delegate.mapView.addScreenMarkers(markers, desc: nil) {
            delegate.addComponents(key: key, value: components)
        }
        
        if let tafs = observations as? [Taf] {
            renderTimestamp(date: tafs.map { $0.to }.max()!, suffix: "forecast")
        } else {
            renderTimestamp(date: observations.map { $0.datetime }.min()!, suffix: "ago")
        }
    }
    
    private func renderTimestamp(date: Date, suffix: String) {
        let seconds = abs(date.timeIntervalSinceNow)
        
        let formatter = DateComponentsFormatter()
        if seconds < 3600*6 {
            formatter.allowedUnits = [.hour, .minute]
        } else {
            formatter.allowedUnits = [.day, .hour]
        }
        formatter.unitsStyle = .brief
        formatter.zeroFormattingBehavior = .dropLeading

        let status = formatter.string(from: seconds)!
        
        delegate.setStatus(text: "\(status) \(suffix)", color: ColorRamp.color(for: date))
    }
    
    func annotation(object: Any, parentFrame: CGRect) -> UIView? {
        if let observation = object as? Observation, let value = observationValue(observation) {
            return ObservationCalloutView(value: value, obs: observation, ramp: ramp, parentFrame: parentFrame)
        } else {
            return nil
        }
    }
}
