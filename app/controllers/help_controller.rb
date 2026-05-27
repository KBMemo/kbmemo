# frozen_string_literal: true

class HelpController < ApplicationController
  include NotebookShowSupport

  after_action :verify_authorized, only: :show

  skip_before_action :require_authentication

  def show
    @notebook = HelpNotebook.find!
    authorize @notebook, :show?
    load_notebook_show!(@notebook)
    render "notebooks/show"
  end
end
