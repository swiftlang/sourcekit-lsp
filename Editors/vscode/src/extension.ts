'use strict';
import * as vscode from 'vscode';
import * as langclient from 'vscode-languageclient/node';
import { activateInlayHints } from './inlayHints';

export async function activate(context: vscode.ExtensionContext): Promise<void> {
    const config = vscode.workspace.getConfiguration('sourcekit-lsp');

    const sourcekit: langclient.Executable = {
        command: config.get<string>('serverPath', 'sourcekit-lsp'),
        args: config.get<string[]>('serverArguments', [])
    };

    const toolchain = config.get<string>('toolchainPath', '');
    if (toolchain) {
        sourcekit.options = { env: { ...process.env, SOURCEKIT_TOOLCHAIN_PATH: toolchain } };
    }

    const serverOptions: langclient.ServerOptions = sourcekit;

    let clientOptions: langclient.LanguageClientOptions = {
        documentSelector: [
            'swift',
            'cpp',
            'c',
            'objective-c',
            'objective-cpp'
        ],
        synchronize: undefined,
        revealOutputChannelOn: langclient.RevealOutputChannelOn.Never
    };

    const client = new langclient.LanguageClient('sourcekit-lsp', 'SourceKit Language Server', serverOptions, clientOptions);

    context.subscriptions.push(client.start());

    console.log('SourceKit-LSP is now active!');

    await client.onReady();
    activateInlayHints(context, client);
}

export function deactivate() {
}
