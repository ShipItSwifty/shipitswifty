import Testing
@testable import ShipItKit

struct GitCLITests {
    @Test func buildsVersionCommand() {
        let command = GitCLI()
            .version()
            .command()

        #expect(command.executableName == "git")
        #expect(command.arguments == ["--version"])
    }

    @Test func buildsRepositoryScopedCommitCommand() {
        let command = GitCLI()
            .repository(at: "/tmp/repo")
            .commit(message: "chore: update")
            .command()

        #expect(command.arguments == ["-C", "/tmp/repo", "commit", "-m", "chore: update"])
    }

    @Test func buildsShallowCloneCommand() {
        let command = GitCLI()
            .clone(url: "git@example.com:team/certs.git", into: "/tmp/certs", depth: 1)
            .command()

        #expect(command.arguments == [
            "clone",
            "--depth", "1",
            "git@example.com:team/certs.git",
            "/tmp/certs"
        ])
    }

    @Test func buildsRevisionCountCommand() {
        let command = GitCLI()
            .revisionCount()
            .command()

        #expect(command.arguments == ["rev-list", "--count", "HEAD"])
    }
}
