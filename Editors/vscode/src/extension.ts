'use strict';
import * as vscode from 'vscode';
import * as langclient from 'vscode-languageclient';

let client: langclient.LanguageClient;

const IndexVisibilityConfigSection = 'sourcekit-lsp.indexVisibility'

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

    let clientOptions: langclient.LanguageClientOptions = {
        documentSelector: [
            'swift',
            'cpp',
            'c',
            'objective-c',
            'objective-cpp'
        ],
        initializationOptions: config.get<any>('initializationOptions', {})
    };

    client = new langclient.LanguageClient('sourcekit-lsp', 'SourceKit Language Server', serverOptions, clientOptions);

    context.subscriptions.push(client.start());

    client.onNotification

    console.log('SourceKit-LSP is now active!');

    client.onReady().then(() => {
        syncConfiguration();

        vscode.workspace.onDidChangeConfiguration(e => {
            if (e.affectsConfiguration(IndexVisibilityConfigSection)) {
                syncConfiguration();
            }
        });
    });
}

export function deactivate() {
}

function syncConfiguration() {
    const visibilityConfig = vscode.workspace.getConfiguration(IndexVisibilityConfigSection);
    const visibilitySettingsParams: langclient.DidChangeConfigurationParams = {
        settings: {
            'sourcekit-lsp': {
                'indexVisibility': {
                    'targets': visibilityConfig.targets.map((uri: String) => 'uri: ' + uri),
                    'includeTargetDependencies': visibilityConfig.includeTargetDependencies
                }
            }
        }
    }

    client.sendNotification(
        langclient.DidChangeConfigurationNotification.type,
        visibilitySettingsParams,
    )
}
