# Release

After the `dev` to `main` PR merges, manually dispatch the single workflow with a semantic version and exact SHA. Normal new releases require the current `main` SHA and no pre-existing tag. Recovery of an existing unpublished tag is allowed only when it already resolves to that SHA and is reachable from `main`.

The publish job is single-instance, has a 20-minute timeout, and never retries automatically. It checks out trusted operations code separately from the exact release source, imports the fixed P12 into an ephemeral keychain, then:

1. validates version, build, changelog, repository, source SHA, and source fingerprint;
2. builds the Release app without local publication state;
3. adds source attestation and signs with the fixed certificate;
4. verifies bundle metadata, certificate SHA-256, designated identity, sealed resources, DMG contents, and checksum;
5. creates the tag only after verification, creates a draft with both assets, then publishes it.

On failure the workflow removes any draft and any new tag it created. Existing tags are never moved or deleted. The temporary keychain and P12 are removed on every exit.

There is no local release command, fallback workflow, polling, receipt, resume, or recovery state.
