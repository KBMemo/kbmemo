import { EditorState } from '@codemirror/state'
import { Decoration, EditorView } from '@codemirror/view'
import { basicSetup } from 'codemirror'
import {
  createAsciidocHighlight,
  configureVanillaHost,
  createLivePreview,
} from '@kbmemo/adoc-editor'
import 'highlight.js/styles/github.min.css'
import '@kbmemo/adoc-preview/preview_hljs.css'

configureVanillaHost({ memoBase: '/memos' })
const asciidocHighlight = createAsciidocHighlight({ Decoration, EditorView })

const initialSource = `= Demo memo

This is a *minimal* AsciiDoc editor demo using link:https://kbmemo.net[kbmemo] packages.

* item one
* item two

NOTE: Live preview updates as you type.
`

let source = initialSource

const preview = createLivePreview({
  previewEl: document.getElementById('preview-pane'),
  getMemoId: () => null,
  getSource: () => source,
})

new EditorView({
  state: EditorState.create({
    doc: initialSource,
    extensions: [
      basicSetup,
      ...asciidocHighlight,
      EditorView.updateListener.of((update) => {
        if (!update.docChanged) return
        source = update.state.doc.toString()
        preview.scheduleRender()
      }),
    ],
  }),
  parent: document.getElementById('source-pane'),
})
