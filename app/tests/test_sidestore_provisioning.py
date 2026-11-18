"""Checks that the built-in SideStore asks Apple once for a new anisette
machine, and tells Cartouche what Apple answered
(app/patches/sidestore/0024):

- a sign-in that needs a new machine provisions it from this iPhone
  straight to Apple, with AnisetteKit's AnisetteClient, whichever anisette
  server signs it: CartoucheAnisette's loop over the Cartouche Installer's
  servers ends on Apple's answer, before the next server, and goes on with
  the next one on any other error;
- Apple's answer is an error of AnisetteKit's whose words name one of the
  steps of the provisioning, as the AnisetteKit SideStore builds with words
  them, and the answers of the server it could not read name none: a new
  AnisetteKit has its words read again (Sources/AnisetteClient.swift and
  AnisetteDataResponse.swift), then added to ANISETTEKIT_WORDS;
- the outcome Cartouche reads gives that answer as the family
  provisioning, with its kind, its HTTP status, the service and the step,
  and Cartouche tells a cause and its own words from it;
- provisioningAnswer itself, built and run with Swift where there is one,
  with AnisetteKit's words: Apple's HTTP errors and the answers of Apple's
  it could not read, at each step, and none of the others.

SideStore's sources are read as app/scripts/prepare.sh leaves them, every
patch applied. Needs the SideStore submodule, with SideSign.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_sidestore_outcome import LAUNCHER, SIDESTORE, block, patched

ANISETTE = "SideStore/Core/Anisette/CartoucheAnisette.swift"
OUTCOME = "SideStore/Intents/CartoucheOutcome.swift"
RESOLVED = [
    SIDESTORE / "AltStore.xcodeproj" / "project.xcworkspace" / "xcshareddata" / "swiftpm" / "Package.resolved",
    SIDESTORE / "Dependencies" / "SideSign" / "Package.resolved",
]

# AnisetteKit's errors, by the revision SideStore builds with: Apple's
# answers to the provisioning (AnisetteClient's sendRequest, with each
# step's endpoint, and its answers it could not read), with the step
# Cartouche's measurements name, and the answers of the anisette server it
# could not read, which are no answer of Apple's.
ANISETTEKIT_WORDS = {
    "db8b41022697b6c19be8a5f01a1ce834145a2a26": {
        "apple": [
            ("httpError", "Apple lookup endpoint returned HTTP {status}", "lookup"),
            ("httpError", "Apple SPIM endpoint returned HTTP {status}", "start"),
            ("httpError", "Apple PTM/TK endpoint returned HTTP {status}", "finish"),
            ("invalidResponse", "Failed to parse provisioning URLs from lookup", "lookup"),
            ("invalidResponse", "Failed to parse spim from Apple response", "start"),
            ("invalidResponse", "Failed to parse ptm/tk from Apple response", "finish"),
        ],
        "server": [
            ("invalidResponse", "Missing X-Apple-I-MD or X-Apple-I-MD-M from response"),
            ("invalidResponse", "Bad JSON from start_provision"),
            ("invalidResponse", "Missing/invalid cpim_base64 or session"),
            ("invalidResponse", "Missing/invalid adi_pb_base64"),
        ],
    },
}

# AnisetteKit's error, as that revision declares it (Sources/AnisetteError.swift).
ANISETTE_ERROR = """
public enum AnisetteError: Error, Equatable, Sendable {
    case invalidArgument
    case loaderFailed(reason: String)
    case symbolMissing(name: String)
    case readFailure
    case invalidResponse(reason: String)
    case adiError(code: Int32, description: String)
    case librariesNotFound(reason: String)
    case httpError(statusCode: Int, message: String)
}
"""


def anisettekit_revision() -> str:
    revisions = set()
    for path in RESOLVED:
        if not path.exists():
            raise AssertionError(f"{path} is missing: run git submodule update --init --recursive")
        pins = json.loads(path.read_text(encoding="utf-8"))["pins"]
        found = [pin["state"]["revision"] for pin in pins if pin["identity"] == "anisettekit"]
        if len(found) != 1:
            raise AssertionError(f"{path.name} does not pin AnisetteKit once")
        revisions |= set(found)
    if len(revisions) != 1:
        raise AssertionError(f"SideStore and SideSign pin different AnisetteKits: {sorted(revisions)}")
    return revisions.pop()


def steps(anisette: str) -> list:
    """CartoucheAnisette.provisioningSteps: the words, and the step's name."""
    listed = re.search(r"static let provisioningSteps: \[\(words: String, step: String\)\] = \[(.*?)\n    \]", anisette, re.S)
    if not listed:
        raise AssertionError("CartoucheAnisette.provisioningSteps not found")
    return re.findall(r'\("([^"]+)", "(\w+)"\)', listed.group(1))


def step_of(words: str, listed: list):
    """The step provisioningAnswer names for WORDS, as its Swift does."""
    lowered = words.lower()
    return next((step for name, step in listed if name in lowered), None)


class SideStoreProvisioningTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.anisette = patched(ANISETTE)
        cls.outcome = patched(OUTCOME)

    def test_apples_answer_ends_the_loop_before_the_next_server(self):
        self.assertIn("import AnisetteKit", self.anisette)
        fetch = block(self.anisette, "static func fetch(signingIn: Bool)", "CartoucheAnisette.fetch(signingIn:)")
        loop = block(fetch, "for server in self.servers(", "the loop over the servers")
        self.assertEqual(len(re.findall(r"\bfor server in\b", self.anisette)), 1, "one loop over the servers")
        tried = loop.find("return try await self.fetch(from: server,")
        apple = loop.find("catch let error where self.provisioningAnswer(of: error) != nil")
        others = loop.find("lastError = error")
        self.assertGreaterEqual(tried, 0, "the loop no longer asks each server")
        self.assertGreaterEqual(apple, 0, "Apple's answer to a new machine no longer ends the loop")
        self.assertLess(tried, apple)
        self.assertLess(apple, others, "the loop goes on with the next server before Apple's answer is told apart")
        self.assertIn("throw error", block(loop[apple:], "!= nil", "the catch of Apple's answer"))
        # Any other error goes on with the next server, the last one thrown
        # once none answered.
        self.assertRegex(loop[others - 40:others], r"catch\s*\{\s*$")
        self.assertIn("throw lastError ?? SideSign.AnisetteError.allServersFailed", fetch)

    def test_apples_answer_is_named_by_anisettekits_words(self):
        revision = anisettekit_revision()
        self.assertIn(revision, ANISETTEKIT_WORDS,
                      f"SideStore builds with AnisetteKit {revision}: read its errors' words again (AnisetteClient.swift, "
                      "AnisetteDataResponse.swift), then add them to ANISETTEKIT_WORDS")
        words = ANISETTEKIT_WORDS[revision]
        listed = steps(self.anisette)
        self.assertEqual([step for _, step in listed], ["lookup", "start", "finish"])
        for kind, sentence, step in words["apple"]:
            with self.subTest(sentence=sentence):
                self.assertEqual(step_of(sentence.format(status=401), listed), step)
        for kind, sentence in words["server"]:
            with self.subTest(sentence=sentence):
                self.assertIsNone(step_of(sentence, listed), "a server's answer taken for Apple's")
        answer = block(self.anisette, "static func provisioningAnswer(of error: Error)", "provisioningAnswer")
        self.assertIn("switch error as? AnisetteKit.AnisetteError", answer)
        self.assertEqual(set(re.findall(r"case \.(\w+)\(", answer)), {"httpError", "invalidResponse"})
        self.assertRegex(answer, r"guard let step = .*else \{ return nil \}", "words that name no step are Apple's answer")
        # The names the measurements send, as Cartouche's own sources and
        # docs give them.
        failure = (LAUNCHER / "CartoucheFailure.swift").read_text(encoding="utf-8")
        self.assertIn('"reason": lookup, start or finish', failure)

    def test_the_outcome_gives_apples_answer_and_cartouche_reads_it(self):
        save = block(self.outcome, "func save(", "CartoucheOutcome.save")
        told = block(save, "if let answer = CartoucheAnisette.provisioningAnswer(of: error)", "the provisioning in save")
        self.assertIn('outcome["service"] = "provisioning"', told)
        self.assertIn('outcome["reason"] = answer.step', told)
        kind = block(self.outcome, "static func kind(of error: Error)", "CartoucheOutcome.kind(of:)")
        default = kind[kind.index("default:"):]
        self.assertLess(default.index('return ("provisioning", answer.kind)'), default.index("error as NSError"))
        status = block(self.outcome, "static func httpStatus(of error: Error)", "CartoucheOutcome.httpStatus(of:)")
        self.assertIn("return CartoucheAnisette.provisioningAnswer(of: error)?.status", status)

        # Cartouche's cause: Apple's refusal for now, its limit, or its
        # servers' error.
        failure = (LAUNCHER / "CartoucheFailure.swift").read_text(encoding="utf-8")
        cause = block(failure, "var cause: CartoucheFailure.Cause", "CartoucheSideStoreOutcome.cause")
        branch = re.search(r'case "provisioning":\n(.*?)\n        case ', cause, re.S)
        self.assertIsNotNone(branch, "Cartouche tells no cause from Apple's answer to a new machine")
        self.assertEqual(re.findall(r"return \.(\w+)", branch.group(1)), ["tooManyAttempts", "provisioningRefused", "appleServer"])
        # And its words: the refusal waits as Apple's limits do, an error of
        # its servers is one of Apple's answers that could not be read.
        message = (LAUNCHER / "CartoucheSignInMessage.swift").read_text(encoding="utf-8")
        trouble = block(message, "static func trouble(", "CartoucheSignInMessage.trouble")
        self.assertIn("if failure.cause == .provisioningRefused, let http { return .provisioningRefused(status: http) }", trouble)
        self.assertIn('service == "provisioning"', re.search(r"^(.*)\n\s*return \.unreadable\(", trouble, re.M).group(1))
        pauses = block(message, "static func pausesSignIns(", "CartoucheSignInMessage.pausesSignIns")
        self.assertIn(".provisioningRefused?", pauses)
        account = (LAUNCHER / "CartoucheAccount.swift").read_text(encoding="utf-8")
        self.assertEqual(account.count("CartoucheSignInMessage.pausesSignIns(trouble)"), 2,
                         "the sign-in and the step that registers this iPhone both wait")

    @unittest.skipUnless(shutil.which("swiftc"), "Needs Swift")
    def test_provisioning_answer_tells_apples_answers_from_the_others(self):
        section = re.search(r"\n    // MARK: - Apple's answer to a new machine\n(.*?)\n    // MARK: - ", self.anisette, re.S)
        self.assertIsNotNone(section, "the section of Apple's answer not found")
        words = ANISETTEKIT_WORDS[anisettekit_revision()]

        def literal(text):
            return json.dumps(text)

        apple = []
        for kind, sentence, step in words["apple"]:
            if kind == "httpError":
                for status in (401, 403, 429, 503):
                    error = f"AnisetteError.httpError(statusCode: {status}, message: {literal(sentence.format(status=status))})"
                    apple.append(f'expect({error}, kind: "httpError", status: {status}, step: "{step}")')
                # A status that is none is left out.
                error = f"AnisetteError.httpError(statusCode: -1, message: {literal(sentence.format(status=-1))})"
                apple.append(f'expect({error}, kind: "httpError", status: nil, step: "{step}")')
            else:
                error = f"AnisetteError.invalidResponse(reason: {literal(sentence)})"
                apple.append(f'expect({error}, kind: "invalidResponse", status: nil, step: "{step}")')
        others = [f"AnisetteError.invalidResponse(reason: {literal(sentence)})" for _, sentence in words["server"]]
        others += ["AnisetteError.readFailure", 'AnisetteError.adiError(code: -45061, description: "Apple PTM/TK")',
                   "Unrelated()", "URLError(.timedOut)"]
        checks = """
import Foundation

struct Unrelated: Error {}

func expect(_ error: Error, kind: String, status: Int?, step: String) {
    let found = CartoucheAnisette.provisioningAnswer(of: error)
    let expected = CartoucheAnisette.ProvisioningAnswer(kind: kind, status: status, step: step)
    guard found == expected else {
        print("FAILED: \\(error): \\(String(describing: found)), expected \\(expected)")
        exit(1)
    }
}

func expectNone(_ error: Error) {
    if let found = CartoucheAnisette.provisioningAnswer(of: error) {
        print("FAILED: \\(error) taken for Apple's answer: \\(found)")
        exit(1)
    }
}

@main
struct Checks {
    static func main() {
""" + "\n".join("        " + line for line in apple) + "\n" \
            + "\n".join(f"        expectNone({error})" for error in others) + """
        print("provisioningAnswer checks passed")
    }
}
"""
        anisette = "import Foundation\n\nfunc debugLog(_ message: String) {}\n\nenum CartoucheAnisette\n{\n" \
            + section.group(1) + "\n}\n"
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "AnisetteError.swift").write_text(ANISETTE_ERROR, encoding="utf-8")
            (folder / "CartoucheAnisette.swift").write_text(anisette, encoding="utf-8")
            (folder / "Checks.swift").write_text(checks, encoding="utf-8")
            # One module named as AnisetteKit's, so that the patch's
            # AnisetteKit.AnisetteError is the one above.
            built = subprocess.run([
                "swiftc", "-parse-as-library", "-module-name", "AnisetteKit",
                *(str(folder / name) for name in ("AnisetteError.swift", "CartoucheAnisette.swift", "Checks.swift")),
                "-o", str(folder / "checks"), "-module-cache-path", str(folder / "cache"),
            ], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(folder / "checks")], capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("provisioningAnswer checks passed", run.stdout)


if __name__ == "__main__":
    unittest.main()
