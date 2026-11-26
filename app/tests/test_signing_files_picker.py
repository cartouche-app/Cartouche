"""Import signing certificate shows the Files picker a game's IPA is
imported with, which UIKit shows over the page
(launcher/Sources/CartoucheImportPicker.swift), for the certificate (.p12)
and its profile. Up to 0.16.2 the page showed SwiftUI's file importer, in
which a .p12 tapped on an iPhone of iOS 27.3 never came back (issue #353),
which the iPhone simulators of the UI tests may never show: these read
the sources, the UI tests pick the certificate (OwnCertificateUITests)."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "launcher" / "Sources"


class SigningFilesPickerTest(unittest.TestCase):
    def test_import_signing_certificate_shows_the_files_picker_of_the_ipa(self):
        view = (SOURCES / "CartoucheSigningView.swift").read_text()
        self.assertNotIn(".fileImporter(", view, "Import signing certificate shows SwiftUI's file importer again")
        self.assertIn("CartoucheImportPicker.shared.pick(from: file)", view)
        for place in ("certificate", "profile"):
            self.assertIn(f"choose(.{place})", view, f"The {place} is not chosen in the Files picker of the IPA")

    def test_the_picker_takes_any_file_and_copies_a_signing_file(self):
        picker = (SOURCES / "CartoucheImportPicker.swift").read_text()
        cases = re.search(r"enum Place: String \{\s*case ([a-z, ]+)\n", picker)
        self.assertIsNotNone(cases)
        self.assertEqual({case.strip() for case in cases.group(1).split(",")},
                         {"home", "sheet", "guide", "certificate", "profile"})
        self.assertIn("forOpeningContentTypes: place.types, asCopy: place.copies", picker)
        # Any file, as the import took before: one of the wrong kind says why
        # (CartoucheSigningCheck) rather than showing greyed out.
        self.assertIn('case .certificate: return [UTType(filenameExtension: "p12") ?? .data, .data]', picker)
        self.assertIn('case .profile: return [UTType(filenameExtension: "mobileprovision") ?? .data, .data]', picker)
        self.assertIn("var copies: Bool { self == .certificate || self == .profile }", picker)

    def test_the_journal_names_the_pickers_of_a_signing_file(self):
        measures = (SOURCES / "CartouchePickerMeasures.swift").read_text()
        self.assertIn('case "certificate": return "the certificate\'s import"', measures)
        self.assertIn('case "profile": return "the profile\'s import"', measures)


if __name__ == "__main__":
    unittest.main()
