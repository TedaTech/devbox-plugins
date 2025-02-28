/**
 * @type {import('semantic-release').GlobalConfig}
 */
export default {
    branches: [
        "master",
        "main",
        "test",
        "beta",
        "alpha",
    ],
    "plugins": [
        "@semantic-release/commit-analyzer",
        "@semantic-release/release-notes-generator",
        "@semantic-release/github",
    ]
};