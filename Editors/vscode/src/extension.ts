'use strict';
import * as vscode from 'vscode';
import * as langclient from 'vscode-languageclient';

export function activate(context: vscode.ExtensionContext) {

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

    let synchronizeOptions: langclient.SynchronizeOptions = {
        configurationSection: [
            'sourcekit-lsp.indexVisibility'
        ]
    }

    let clientOptions: langclient.LanguageClientOptions = {
        documentSelector: [
            'swift',
            'cpp',
            'c',
            'objective-c',
            'objective-cpp'
        ],
        synchronize: synchronizeOptions,
        initializationOptions: config.get<any>('initializationOptions', {})
    };

    const client = new langclient.LanguageClient('sourcekit-lsp', 'SourceKit Language Server', serverOptions, clientOptions);

    context.subscriptions.push(client.start());

    console.log('SourceKit-LSP is now active!');
}

export function deactivate() {
}
