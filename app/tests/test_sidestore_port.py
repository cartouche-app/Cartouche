"""Checks that the built-in SideStore looks for this iPhone's RemotePairing
port again when its port breaks the connection or does not answer
(app/patches/sidestore/0026):

- the words CartouchePortLookup tells such a port by are still those
  minimuxer gives: those it tells a broken connection by
  (DeviceGatewayError.isVPNDrop), but "no route to host", which LocalDevVPN
  gives whatever the port, and its probe's sentence for a port that does not
  answer (MinimuxerImpl.isReady);
- SideStore's retry looks again on those errors too, for the sign-in's
  check of this iPhone and every other action, and what it found goes in
  the outcome Cartouche reads;
- the retry itself, built and run with Swift where there is one: a port
  that breaks the connection, with the service found at another one, which
  the action goes on with; the service found at the same port, or nowhere;
  a port found that answers no better, which SideStore leaves for the one
  before; one that answers and refuses the pairing, which it keeps; the
  errors it looked again for before, as they were; and the others, without
  any lookup.

A port another service of the iPhone holds answers minimuxer's probe, then
breaks the connection as soon as SideStore speaks: SideStore looked for the
service's port again only when it could not find the iPhone at all, so the
sign-in failed within a second, whatever the player did.

SideStore's sources are read as app/scripts/prepare.sh leaves them, every
patch applied. Needs the SideStore submodule, with minimuxer.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_sidestore_outcome import block, minimuxer_sources, patched

LOOKUP = "SideStore/Core/DeviceApi/CartouchePortLookup.swift"
WRAPPER = "SideStore/Core/DeviceApi/MinimuxerWrapper.swift"
OUTCOME = "SideStore/Intents/CartoucheOutcome.swift"

# The functions of MinimuxerWrapper the checks build, by how each one opens.
FUNCTIONS = (
    "private func isWrongPortError(",
    "private func isRetriableRemotePairingError(",
    "private func withRemotePairingRetry<T>(",
)


def declaration(text: str, opening: str) -> str:
    """The declaration that starts with OPENING, with its whole body."""
    start = text.find(opening)
    if start < 0:
        raise AssertionError(f"MinimuxerWrapper's {opening.split('func ')[1]} not found")
    body = block(text, opening, opening)
    end = text.index(body, start) + len(body)
    return text[start:end] + "}"


def listed_words(text: str) -> list:
    """CartouchePortLookup's words."""
    found = re.search(r"static let words = \[(.*?)\]", text, re.S)
    if not found:
        raise AssertionError("CartouchePortLookup.words not found")
    return re.findall(r'"([^"]+)"', found.group(1))


class SideStorePortTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lookup = patched(LOOKUP)
        cls.wrapper = patched(WRAPPER)
        cls.outcome = patched(OUTCOME)
        cls.minimuxer = minimuxer_sources()

    def test_the_words_are_still_minimuxers(self):
        words = listed_words(self.lookup)
        drop = block(self.minimuxer["Sources/MinimuxerError.swift"], "var isVPNDrop: Bool", "isVPNDrop")
        dropped = re.findall(r'lower\.contains\("([^"]+)"\)', drop)
        self.assertIn("connection reset", dropped)
        # Every word of a broken connection, but LocalDevVPN's.
        self.assertEqual(set(words) - {"tcp port poll failed"}, set(dropped) - {"no route to host"})
        # The probe's sentence for a port that does not answer, through
        # LocalDevVPN, as minimuxer's readiness check gives it.
        ready = block(self.minimuxer["Sources/MinimuxerImpl.swift"], "func isReady(withNetworkCheck: Bool", "isReady")
        sentences = [sentence.lower() for sentence in re.findall(r'\.invalidVPN\("([^"]+)"\)', ready)]
        self.assertTrue(any("tcp port poll failed" in sentence for sentence in sentences), sentences)
        self.assertTrue(all(word == word.lower() for word in words), "the words are matched lowercased")

    def test_every_action_looks_again_and_says_what_it_found(self):
        retriable = declaration(self.wrapper, FUNCTIONS[1])
        self.assertIn("if isWrongPortError(error) {", retriable)
        retry = declaration(self.wrapper, FUNCTIONS[2])
        self.assertIn("CartoucheOutcome.lookedForPort(", retry)
        # The sign-in's check of this iPhone, and the readiness check every
        # pipeline makes, go through the retry.
        ready = declaration(self.wrapper, "public func ensureMinimuxerReady()")
        self.assertIn("try await withRemotePairingRetry {", ready)
        check = patched("SideStore/Intents/CartoucheDeviceCheck.swift")
        self.assertIn("try await ensureMinimuxerReady()", check)
        # The outcome gives what the last lookup of the action found, and
        # forgets it as an action starts.
        save = block(self.outcome, "func save(", "CartoucheOutcome.save")
        self.assertIn('outcome["portLookup"] = found.rawValue', save)
        start = block(self.outcome, "init(action: Action)", "CartoucheOutcome.init")
        self.assertIn("Self.portLookup = nil", start)

    @unittest.skipUnless(shutil.which("swiftc"), "Needs Swift")
    def test_a_port_that_breaks_the_connection_is_looked_for_again(self):
        functions = "\n\n".join(declaration(self.wrapper, opening) for opening in FUNCTIONS)
        program = r'''
import Foundation

enum PairingProtocol { case rppairing, lockdown, unknown }

enum MinimuxerError: Error {
    case noDevice(String), notReachable(String), noConnection(String), invalidVPN(String)
    case invalidPairing(protocol: PairingProtocol, reason: String)
}

enum OperationError: Error {
    case noDevice(reason: String), notReachable(reason: String), unknownUDID
    case noConnection(reason: String), invalidVPN(reason: String), invalidPairingFile(reason: String)
}

struct MinimuxerParams { var remotePairingPort: UInt16? }

final class Gateway { var pairingFileType: PairingProtocol = .rppairing }

final class FakeMinimuxer {
    let gateway = Gateway()
    var port: UInt16 = 49152
    @discardableResult func set(_ params: MinimuxerParams) -> FakeMinimuxer {
        if let port = params.remotePairingPort { self.port = port }
        return self
    }
}

let minimuxer = FakeMinimuxer()
var remotePairingPortCache: UInt16 = 49152
var lastDiscovered = 0

extension UserDefaults {
    var isAutoRetryRemotePairingPortEnabled: Bool { true }
    var lastDiscoveredRemotePairingPort: Int {
        get { lastDiscovered }
        set { lastDiscovered = newValue }
    }
}

/// Where Bonjour finds the RemotePairing service, and how many times it
/// was asked.
var service: UInt16? = nil
var lookups = 0

func resolveDiscoveredRemotePairingPortThrottled() async -> UInt16? {
    lookups += 1
    if let service { lastDiscovered = Int(service) }
    return service
}

enum CartoucheOutcome {
    static var found: CartouchePortLookup.Found? = nil
    static func lookedForPort(_ found: CartouchePortLookup.Found) { self.found = found }
}

func debugLog(_ message: @autoclosure () -> String) {}

''' + functions + r'''

/// What each port of this iPhone does with SideStore's request: answers,
/// or fails as given.
var ports: [UInt16: Error] = [:]
var tried: [UInt16] = []

func reach() async throws -> String {
    tried.append(minimuxer.port)
    if let error = ports[minimuxer.port] { throw error }
    return "reached"
}

/// The action through SideStore's retry: what it gave, or its error.
func run() async -> (String?, Error?) {
    do { return (try await withRemotePairingRetry { try await reach() }, nil) } catch { return (nil, error) }
}
'''
        checks = r'''
import Foundation

let reset = "Connection reset by peer (os error 54)"
let probe = "VPN tunnel iface is up and tunnel peer IP 10.7.0.1 is known, but TCP port poll failed — device may be unreachable on this interface"

func expect(_ condition: Bool, _ what: String) {
    if !condition {
        print("FAILED: \(what)")
        exit(1)
    }
}

func start(_ given: [UInt16: Error], at port: UInt16 = 49152, service found: UInt16?) {
    ports = given
    tried = []
    minimuxer.port = port
    remotePairingPortCache = port
    lastDiscovered = 0
    service = found
    lookups = 0
    CartoucheOutcome.found = nil
}

// Another service holds 49152 and breaks the connection; the RemotePairing
// service is at 49153: what 0026 is for.
start([49152: OperationError.invalidVPN(reason: reset)], service: 49153)
var (reached, error) = await run()
expect(reached == "reached", "a port that breaks the connection is looked for again, and the action goes on")
expect(tried == [49152, 49153], "the action goes on at the port found")
expect(remotePairingPortCache == 49153 && minimuxer.port == 49153 && lastDiscovered == 49153, "the port found is kept")
expect(CartoucheOutcome.found == .moved, "the outcome says the port moved")

// Minimuxer's own error, and an early end of the connection.
start([49152: MinimuxerError.invalidVPN("early eof")], service: 49153)
(reached, error) = await run()
expect(reached == "reached", "minimuxer's invalidVPN for an early end is looked for again")

// A port that does not answer the probe.
start([49152: OperationError.invalidVPN(reason: probe)], service: 49153)
(reached, error) = await run()
expect(reached == "reached", "a port that does not answer is looked for again")

// The service at the port SideStore used: the connection broke for
// another reason.
start([49152: OperationError.invalidVPN(reason: reset)], service: 49152)
(reached, error) = await run()
expect(reached == nil && tried == [49152], "the service at the same port: no second try")
expect(CartoucheOutcome.found == .same, "the outcome says the port is the same")
expect(remotePairingPortCache == 49152, "the port stays")

// Bonjour finds nothing: no Local Network access, or not in time.
start([49152: OperationError.invalidVPN(reason: reset)], service: nil)
(reached, error) = await run()
expect(reached == nil && tried == [49152], "no service found: no second try")
expect(CartoucheOutcome.found == .notFound, "the outcome says the service was not found")

// A port found that answers no better, as that of another device on the
// network: back to the port before.
start([49152: OperationError.invalidVPN(reason: reset), 49153: OperationError.invalidVPN(reason: probe)], service: 49153)
(reached, error) = await run()
expect(tried == [49152, 49153], "the port found is tried")
if case OperationError.invalidVPN(let sentence)? = error {
    expect(sentence == probe, "the port found's error comes back")
} else {
    expect(false, "the port found's error comes back")
}
expect(remotePairingPortCache == 49152 && minimuxer.port == 49152 && lastDiscovered == 49152,
       "a port found that answers no better is left for the one before")
expect(CartoucheOutcome.found == .moved, "the outcome says the port moved")

// A port found that answers and refuses the pairing: the service is there.
start([49152: OperationError.invalidVPN(reason: reset),
       49153: OperationError.invalidPairingFile(reason: "Handshake failed: pairing")], service: 49153)
(reached, error) = await run()
if case OperationError.invalidPairingFile? = error {} else { expect(false, "the pairing refused comes back") }
expect(remotePairingPortCache == 49153 && minimuxer.port == 49153, "a port found that answers is kept")

// SideStore's own retry, for an iPhone it could not find, as it was: the
// port found kept whatever it answers, and nothing in the outcome.
start([49152: OperationError.noDevice(reason: "no device"), 49153: OperationError.invalidVPN(reason: reset)], service: 49153)
(reached, error) = await run()
expect(tried == [49152, 49153] && remotePairingPortCache == 49153, "SideStore's own retry keeps the port found")
expect(CartoucheOutcome.found == nil, "SideStore's own retry leaves nothing in the outcome")

// No Wi-Fi, LocalDevVPN's own routing, a refused pairing: no lookup.
for given in [OperationError.noConnection(reason: "No wifi interface satisfied"),
              OperationError.invalidVPN(reason: "Network is unreachable: no route to host"),
              OperationError.invalidPairingFile(reason: "Handshake failed: pairing")] {
    start([49152: given], service: 49153)
    (reached, error) = await run()
    expect(reached == nil && lookups == 0 && tried == [49152], "no lookup for \(given)")
    expect(CartoucheOutcome.found == nil, "nothing in the outcome for \(given)")
}

print("Port lookup checks passed")
'''
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "CartouchePortLookup.swift").write_text(self.lookup, encoding="utf-8")
            (folder / "MinimuxerWrapper.swift").write_text(program, encoding="utf-8")
            (folder / "main.swift").write_text(checks, encoding="utf-8")
            built = subprocess.run([
                "swiftc", "-module-name", "PortChecks", str(folder / "CartouchePortLookup.swift"),
                str(folder / "MinimuxerWrapper.swift"), str(folder / "main.swift"), "-o", str(folder / "checks"), "-module-cache-path", str(folder / "cache"),
            ], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(folder / "checks")], capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("Port lookup checks passed", run.stdout)


if __name__ == "__main__":
    unittest.main()
