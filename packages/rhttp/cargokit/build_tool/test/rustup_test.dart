import 'package:build_tool/src/rustup.dart';
import 'package:test/test.dart';

void main() {
  test('retains installed pinned releases alongside named channels', () {
    expect(
      officialToolchainNames('''
stable-aarch64-apple-darwin (default)
1.92.0-aarch64-apple-darwin (active)
1.92.0-x86_64-unknown-linux-gnu
nightly-2026-10-01-aarch64-apple-darwin
beta-x86_64-pc-windows-msvc
'''),
      [
        'stable-aarch64-apple-darwin',
        '1.92.0-aarch64-apple-darwin',
        '1.92.0-x86_64-unknown-linux-gnu',
        'nightly-2026-10-01-aarch64-apple-darwin',
        'beta-x86_64-pc-windows-msvc',
      ],
    );
  });

  test('accepts rustup bare release names and Windows line endings', () {
    expect(officialToolchainNames('  1.92.0 (default)\r\nstable\r\n'), [
      '1.92.0',
      'stable',
    ]);
  });

  test('does not confuse custom toolchains or empty output with releases', () {
    expect(
      officialToolchainNames('custom-local\nstableish\nnightlyish\n\n'),
      isEmpty,
    );
  });
}
