# frozen_string_literal: true

class MemoDiagramsController < ApplicationController
  before_action :set_memo
  before_action :set_source_relative, only: %i[edit update preview]

  after_action :verify_authorized

  def new
    authorize @memo, :edit_diagram?
  end

  def create
    authorize @memo, :edit_diagram?
    result = MemoDiagrams.create!(
      @memo,
      name: params.require(:name),
      engine: params.require(:engine)
    )
    redirect_to edit_memo_diagram_path(@memo, diagram_key_param(result[:source_relative])),
      notice: "ダイアグラムを作成しました。本文に #{result[:asciidoc]} を挿入してください。"
  rescue MemoDiagrams::Error, MemoDiagram::InvalidPath => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def edit
    authorize @memo, :show_diagram?
    @source = MemoDiagrams.new.read_source(@memo, source_relative: @source_relative)
    @engine = MemoDiagram.engine_for_filename(@source_relative)
  rescue MemoDiagrams::Error => e
    redirect_to edit_memo_path(@memo), alert: e.message
  end

  def preview
    authorize @memo, :show_diagram?
    svg = MemoDiagrams.preview_render(source_relative: @source_relative, source: params.require(:source))
    render json: { svg: svg }
  rescue MemoDiagram::InvalidPath, MemoDiagramRenderer::Error, MemoDiagramRenderer::Unavailable => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    authorize @memo, :edit_diagram?
    MemoDiagrams.save_and_render!(
      @memo,
      source_relative: @source_relative,
      source: params.require(:source)
    )
    redirect_to edit_memo_diagram_path(@memo, params[:diagram_key]),
      notice: "ダイアグラムを保存し、SVG を更新しました。"
  rescue MemoDiagrams::Error, MemoDiagram::InvalidPath, MemoDiagramRenderer::Error, MemoDiagramRenderer::Unavailable => e
    @source = params[:source]
    @engine = MemoDiagram.engine_for_filename(@source_relative)
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  private

  def set_memo
    @memo = policy_scope(Memo).find(params[:memo_id])
  end

  def set_source_relative
    key = params[:diagram_key].to_s
    @source_relative = MemoDiagram.source_relative_path(key)
  rescue MemoDiagram::InvalidPath
    raise ActiveRecord::RecordNotFound
  end

  def diagram_key_param(source_relative)
    source_relative.sub(%r{\Adiagrams/}, "")
  end
end
