# frozen_string_literal: true

require "test_helper"

class ClipLinkedImageAdocTest < ActiveSupport::TestCase
  test "formats local asset with link attribute" do
    adoc = ClipLinkedImageAdoc.format(
      src: "badge.png",
      alt: "GitHub Release",
      link: "https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest"
    )

    assert_equal(
      "image::badge.png[GitHub Release, link=https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest]",
      adoc
    )
  end

  test "formats remote https image inline with link attribute" do
    src = "https://camo.githubusercontent.com/badge.png"
    adoc = ClipLinkedImageAdoc.format(
      src: src,
      alt: "GitHub Release",
      link: "https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest"
    )

    assert_equal(
      "image:#{src}[GitHub Release, link=https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest]",
      adoc
    )
  end
end
