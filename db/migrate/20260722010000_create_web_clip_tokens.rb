# frozen_string_literal: true

class CreateWebClipTokens < ActiveRecord::Migration[8.1]
  def up
    create_table :web_clip_tokens do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.timestamps
    end
    add_index :web_clip_tokens, :token_digest, unique: true

    execute <<~SQL.squish
      INSERT INTO web_clip_tokens (account_id, name, token_digest, token_prefix, created_at, updated_at)
      SELECT id, '移行済みトークン', web_clip_token_digest, web_clip_token_prefix,
             COALESCE(web_clip_token_created_at, CURRENT_TIMESTAMP), CURRENT_TIMESTAMP
      FROM accounts
      WHERE web_clip_token_digest IS NOT NULL
    SQL

    remove_index :accounts, :web_clip_token_digest
    remove_columns :accounts, :web_clip_token_digest, :web_clip_token_prefix, :web_clip_token_created_at
  end

  def down
    add_column :accounts, :web_clip_token_digest, :string
    add_column :accounts, :web_clip_token_prefix, :string
    add_column :accounts, :web_clip_token_created_at, :datetime
    add_index :accounts, :web_clip_token_digest, unique: true

    execute <<~SQL.squish
      UPDATE accounts
      SET web_clip_token_digest = latest.token_digest,
          web_clip_token_prefix = latest.token_prefix,
          web_clip_token_created_at = latest.created_at
      FROM (
        SELECT DISTINCT ON (account_id) account_id, token_digest, token_prefix, created_at
        FROM web_clip_tokens
        ORDER BY account_id, created_at DESC, id DESC
      ) latest
      WHERE accounts.id = latest.account_id
    SQL

    drop_table :web_clip_tokens
  end
end
