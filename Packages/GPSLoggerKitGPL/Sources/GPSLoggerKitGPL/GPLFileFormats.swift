import Foundation
import GPSLoggerKit

/// Credit for the source a ported format or driver is based on, shown in the app's about window.
public struct Credit: Sendable, Hashable {
    /// Project, e.g. "GPSBabel".
    public var project: String
    /// Copyright holders as stated in the source, e.g. "Robert Lipe and contributors".
    public var authors: String
    /// License of the source, as an SPDX identifier, e.g. "GPL-2.0-or-later".
    public var license: String
    /// Where the source code of the version used is available.
    public var sourceURL: URL

    public init(project: String, authors: String, license: String, sourceURL: URL) {
        self.project = project
        self.authors = authors
        self.license = license
        self.sourceURL = sourceURL
    }
}

/// The formats of this package, to be combined with the GPSLoggerKit catalog:
///
/// ```swift
/// let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
/// ```
public enum GPLFileFormats {
    /// All formats of this package. Identifiers differ from those in GPSLoggerKit.
    public static let all: [any FileFormat] = [
        SkyTraqBinFileFormat(), MTKBinFileFormat(), M241BinFileFormat(), WintecTK1FileFormat(), WintecBinFileFormat(),
        WintecTESFileFormat(), SBNFileFormat(), SBPFileFormat(), GoPalFileFormat(), MagellanFileFormat(),
        AlanFileFormat(),  // last: detected by plausible coordinates only (change alan-port, design D4)
    ]

    /// The sources of the ported formats and device protocols, one entry per source project.
    public static let credits: [Credit] = [
        Credit(project: "GPSBabel",
               authors: "Robert Lipe, Mathias Adam, Per Borgentun, Andy Armstrong, Rodney Lorrimar, Tom Hughes, "
                   + "Jürgen Neumann, Andreas Grimme, Gunar Megger and the GPSBabel contributors",
               license: "GPL-2.0-or-later",
               sourceURL: URL(string: "https://github.com/GPSBabel/gpsbabel/tree/gpsbabel_1_7_0")!),
        Credit(project: "igotu2gpx", authors: "Michael Hofmann", license: "GPL-3.0-or-later",
               sourceURL: URL(string: "https://launchpad.net/igotu2gpx/0.3/0.3.0")!),
    ]
}
