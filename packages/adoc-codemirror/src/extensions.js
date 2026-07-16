import { Extensions } from '@asciidoctor/core'

/**
 * Shared Extension registry for load() and convert().
 * Add custom inlineMacro / treeProcessor hooks here.
 */
export function createExtensionRegistry() {
  const registry = Extensions.create()

  // Built-in kbd:/menu: are handled by sub_macros when :experimental: is set.
  // Register custom inline macros below, e.g.:
  //
  // registry.inlineMacro('badge', function () {
  //   this.process(function (parent, target) {
  //     return this.createInline(parent, 'quoted', target, { type: 'strong' })
  //   })
  // })

  return registry
}
