---
layout: page
title: Support
permalink: /support/
---

## Getting help

- **Bugs and feature requests**: [github.com/nxthdr/parlotte/issues](https://github.com/nxthdr/parlotte/issues)
- **Security concerns**: email the maintainer listed on the GitHub repo. Please do not open public issues for security vulnerabilities.

## Frequently asked questions

### What is Matrix?

Matrix is an open, federated, end-to-end encrypted messaging network. Think of it like email: no single company controls it, your identity is tied to a server you pick (a *homeserver*), and servers talk to each other. Learn more at [matrix.org](https://matrix.org).

### Which homeserver should I use?

For a quick start, sign up on [matrix.org](https://app.element.io/#/register). For more privacy or higher limits, pick a community homeserver or self-host [Synapse](https://github.com/element-hq/synapse).

### I forgot my password — what happens to my encrypted messages?

Message content is protected by encryption keys that live on your devices, not on the server. If you enabled **key backup**, you can restore your history after signing in by entering your recovery key. If you didn't, the encrypted messages stay encrypted and can't be recovered — that's by design.

### What is a recovery key?

A 48-character secret that protects your backed-up encryption keys. If you lose access to every signed-in device, it is the only way to restore your encrypted history. Save it somewhere safe — a password manager is a good choice.

### How does end-to-end encryption work in Parlotte?

Private rooms use the Matrix Megolm protocol. Your keys are generated and stored on your device. To trust a new device, you verify it by comparing emoji with a device you already trust (cross-signing via SAS).

### Can I use Parlotte with any Matrix homeserver?

Yes. Parlotte works with any standard Matrix homeserver — Synapse, Conduit, Dendrite, matrix.org, and private deployments.

### What macOS version do I need?

macOS 15 (Sequoia) or later.

### Is Parlotte open source?

Yes. Source code is available at [github.com/nxthdr/parlotte](https://github.com/nxthdr/parlotte), licensed under MIT.

### Is there an iOS version?

Planned. Parlotte's core is written in Rust and shared between platforms, so iOS is the natural next step. Track progress on GitHub.

### Does Parlotte send my messages or metadata to anyone other than my homeserver?

No. See the [privacy policy](/parlotte/privacy/) for details.
