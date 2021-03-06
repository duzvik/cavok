//
//  Maply+Additions.swift
//  CAVOK
//
//  Created by Juho Kolehmainen on 07.09.16.
//  Copyright © 2016 Juho Kolehmainen. All rights reserved.
//

import Foundation

extension MaplyBoundingBox {
    func inside(_ c: MaplyCoordinate) -> Bool {
        return ((self.ll.x < c.x) && (self.ll.y < c.y) && (c.x < self.ur.x) && (c.y < self.ur.y))
    }
    
    func tiles(zoom: Int32) -> (ll: MaplyTileID, ur: MaplyTileID) {
        let ll = self.ll.tile(offsetX: 0, offsetY: 1, zoom: zoom)
        let ur = self.ur.tile(offsetX: 1, offsetY: 0, zoom: zoom)
        
        return (ll: ll, ur: ur)
    }
}

extension MaplyCoordinate {
    static let kRadiansToDegrees: Float = 180.0 / .pi
    static let kDegreesToRadians: Float = .pi / 180.0
    static let earthRadius = Float(6371.01) // Earth's radius in Kilometers
    
    var deg : MaplyCoordinate {
        get {
            return MaplyCoordinate(x: self.x * MaplyCoordinate.kRadiansToDegrees, y: self.y * MaplyCoordinate.kRadiansToDegrees)
        }
    }
    
    func tile(offsetX: Int, offsetY: Int, zoom: Int32) -> MaplyTileID {
        let scale = pow(2.0, Double(zoom))
        
        let lon = Double(self.x * MaplyCoordinate.kRadiansToDegrees)
        let x = Int32(floor((lon + 180.0) / 360.0 * scale))
    
        let lat = Double(self.y)
        let y  = Int32(floor((1.0 - log( tan(lat) + 1.0 / cos(lat)) / M_PI) / 2.0 * scale))
        
        return MaplyTileID(x: x + offsetX, y: y + offsetY, level: zoom)
    }
    
    // finds a new location on a straight line towards a second location, given distance in kilometers.
    func locationAt(distance:Int, direction:Int) -> MaplyCoordinate {
        let lat1 = self.y
        let lon1 = self.x
        let dRad = Float(direction) * MaplyCoordinate.kDegreesToRadians
        
        let nD = Float(distance) //distance travelled in km
        let nC = nD / MaplyCoordinate.earthRadius
        let nA = acosf(cosf(nC)*cosf(Float(M_PI/2) - lat1) + sinf(Float(M_PI/2) - lat1)*sinf(nC)*cosf(dRad))
        let dLon = asin(sin(nC)*sin(dRad)/sin(nA))
        
        let lat2 = (Float(M_PI/2) - nA)
        let lon2 = (dLon + lon1)
        
        return MaplyCoordinateMake(lon2, lat2)
    }
}

extension MaplyTileID {

    private static func coord(x: Int32, y: Int32, z: Int32) -> MaplyCoordinate {
        let scale = pow(2, Double(z))
        
        let lon = Double(x) / scale * 360.0 - 180.0
        
        let n = M_PI - 2 * M_PI * Double(y) / scale
        let lat = 180 / M_PI * atan(0.5*(exp(n) - exp(-n)))
        
        return MaplyCoordinateMakeWithDegrees(Float(lon), Float(lat))
    }
    
    var coordinate: MaplyCoordinate {
        get {
            return MaplyTileID.coord(x: self.x, y: self.y, z: self.level)
        }
    }
    
    var bbox: MaplyBoundingBox {
        get {
            return MaplyBoundingBox(
                ll: MaplyTileID.coord(x: self.x, y: self.y + 1, z: self.level),
                ur: MaplyTileID.coord(x: self.x + 1, y: self.y, z: self.level)
            )
        }
    }
}

extension MaplySphericalMercator {
    func geo(toLocalBox bbox: MaplyBoundingBox) -> MaplyBoundingBox {
        return MaplyBoundingBox(
            ll: geo(toLocal: bbox.ll),
            ur: geo(toLocal: bbox.ur)
        )
    }
}
