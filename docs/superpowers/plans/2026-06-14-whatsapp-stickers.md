# WhatsApp Stickers (Figurinhas) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let agents create/save stickers (from images, camera, or received stickers) and send native WhatsApp stickers, with a sticker button in both the desktop and mobile (PWA) composers.

**Architecture:** A sent sticker is a normal `outgoing` message with `content_type: 'sticker'` plus a `.webp` attachment, built by the native `Messages::MessageBuilder`. The native outgoing pipeline (`SendOnWhatsappService → channel.send_message → WhatsappCloudService#send_message`) carries it; we add a `content_type == 'sticker'` branch that posts `type: 'sticker'` to the WhatsApp Cloud API via `{ link: attachment.download_url }` (mirrors the existing `send_attachment_message`). The library is a dedicated `stickers` table (per-account) + per-user recents in `user.ui_settings`. Conversion to 512×512 webp (static + animated) uses libvips (`ruby-vips`).

**Tech Stack:** Rails 7, ActiveStorage, ruby-vips (libvips), Vue 3 `<script setup>`, Vuex, Tailwind, RSpec, vitest.

**Spec:** `docs/superpowers/specs/2026-06-14-whatsapp-stickers-design.md`

**Refinement vs spec:** The spec mentioned `upload_media`. During planning we confirmed the existing `send_attachment_message` sends media by public **link** (`attachment.download_url`), not by upload. The sticker send path mirrors that (leaner, no media-upload/caching code). `upload_media` is dropped.

**Test environment notes:**
- Ruby: prefer Docker container (`./dev.sh shell`) — libvips is installed there. On host, run with `rbenv` and the shared infra (`POSTGRES_HOST=127.0.0.1`, etc.), and ensure libvips is present (`ruby -e "require 'vips'"`). Run specs **without** `.env` (rename to `.env.bak` if present).
- JS: `pnpm test <file>` and `pnpm eslint <file>` run on host.

---

## File Structure

**Backend (new):**
- `db/migrate/<ts>_create_stickers.rb` — `stickers` table
- `app/models/sticker.rb` — model + recents helpers
- `app/policies/sticker_policy.rb` — authorization
- `app/controllers/api/v1/accounts/stickers_controller.rb` — REST + send
- `app/services/stickers/converter_service.rb` — image → 512² webp (libvips)

**Backend (modified):**
- `config/routes.rb` — `stickers` resource routes
- `app/models/account.rb` — `has_many :stickers`
- `app/services/whatsapp/providers/whatsapp_cloud_service.rb` — `send_sticker_message` + branch

**Frontend (new):**
- `app/javascript/dashboard/api/stickers.js`
- `app/javascript/dashboard/composables/useStickers.js`
- `app/javascript/dashboard/components-next/message/bubbles/Sticker.vue`
- `app/javascript/dashboard/components/widgets/conversation/StickerPicker/StickerPicker.vue`
- `app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue`

**Frontend (modified):**
- `app/javascript/dashboard/components-next/message/Message.vue` — register Sticker bubble
- `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` — desktop button
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` — host desktop picker
- `app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue` — mobile button + sheet
- `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue` (+ mobile menu) — "Save as sticker"
- i18n: `en/pt/pt_BR` dashboard `*.json`, `mobile.json`, `config/locales/en.yml`

---

## Task 1: `stickers` table + Sticker model

**Files:**
- Create: `db/migrate/<ts>_create_stickers.rb`
- Create: `app/models/sticker.rb`
- Modify: `app/models/account.rb`

- [ ] **Step 1: Generate the migration file**

Run: `cd /home/wital/chatwit && bundle exec rails generate migration CreateStickers`
Then replace its contents with:

```ruby
class CreateStickers < ActiveRecord::Migration[7.1]
  def change
    create_table :stickers do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.boolean :animated, null: false, default: false
      t.timestamps
    end
    add_index :stickers, :account_id
    add_index :stickers, [:account_id, :created_at]
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bundle exec rails db:migrate`
Expected: `== CreateStickers: migrated` and `db/schema.rb` updated with the `stickers` table.

- [ ] **Step 3: Create the model**

Create `app/models/sticker.rb`:

```ruby
class Sticker < ApplicationRecord
  RECENT_LIMIT = 20

  belongs_to :account
  belongs_to :user, optional: true
  has_one_attached :file

  validates :account_id, presence: true

  # Appends a sticker id to the per-user recents list (newest first, capped).
  def self.touch_recent(user, sticker_id)
    settings = user.ui_settings || {}
    recents = Array(settings['recent_stickers']).reject { |id| id == sticker_id }
    recents.unshift(sticker_id)
    user.update!(ui_settings: settings.merge('recent_stickers' => recents.first(RECENT_LIMIT)))
  end

  # Returns the user's recent stickers in recency order, scoped to the account.
  def self.recent_for(account, user)
    ids = Array(user.ui_settings&.dig('recent_stickers'))
    return none if ids.blank?

    scope = account.stickers.where(id: ids).index_by(&:id)
    ids.filter_map { |id| scope[id] }
  end
end
```

- [ ] **Step 4: Associate on Account**

In `app/models/account.rb`, add to the `has_many` associations block (near the other `has_many` lines):

```ruby
  has_many :stickers, dependent: :destroy_async
```

- [ ] **Step 5: Verify model loads + recents logic in console**

Run:
```bash
bundle exec rails runner "a=Account.first; u=User.first; Sticker.touch_recent(u, 999); puts u.reload.ui_settings['recent_stickers'].inspect"
```
Expected: prints an array containing `999` (no exception). Then clean up: `bundle exec rails runner "u=User.first; u.update!(ui_settings: (u.ui_settings||{}).except('recent_stickers'))"`

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/sticker.rb app/models/account.rb
git commit -m "feat(stickers): add stickers table, model and account association"
```

---

## Task 2: Sticker policy

**Files:**
- Create: `app/policies/sticker_policy.rb`

- [ ] **Step 1: Create the policy**

Create `app/policies/sticker_policy.rb`:

```ruby
class StickerPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def send_sticker?
    true
  end

  def destroy?
    @account_user.administrator? || record.user_id == @user.id
  end
end
```

> Note: `ApplicationPolicy` in this codebase exposes `@user`, `@account`, `@account_user`. Confirm by reading `app/policies/application_policy.rb` before relying on `@account_user`; if the attribute differs, use the same accessor other policies use for admin checks (search: `rg -n "administrator\?" app/policies`).

- [ ] **Step 2: Verify with rubocop**

Run: `bundle exec rubocop app/policies/sticker_policy.rb`
Expected: no offenses.

- [ ] **Step 3: Commit**

```bash
git add app/policies/sticker_policy.rb
git commit -m "feat(stickers): add sticker authorization policy"
```

---

## Task 3: ConverterService — static images

**Files:**
- Create: `app/services/stickers/converter_service.rb`
- Test: `spec/services/stickers/converter_service_spec.rb`

- [ ] **Step 1: Write the failing test (static)**

Create `spec/services/stickers/converter_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Stickers::ConverterService do
  let(:account) { create(:account) }
  let(:user) { create(:user) }

  # 600x400 red PNG generated with libvips (no fixture file needed)
  def png_bytes(width = 600, height = 400)
    Vips::Image.black(width, height).add([255, 0, 0]).cast(:uchar)
         .copy(interpretation: :srgb).write_to_buffer('.png')
  end

  describe 'static image' do
    it 'produces a 512x512 static webp under 100KB' do
      sticker = described_class.new(account: account, user: user, file: upload(png_bytes)).perform

      expect(sticker).to be_persisted
      expect(sticker.animated).to be(false)
      expect(sticker.file).to be_attached
      expect(sticker.file.content_type).to eq('image/webp')

      out = Vips::Image.new_from_buffer(sticker.file.download, '')
      expect(out.width).to eq(512)
      expect(out.height).to eq(512)
      expect(sticker.file.byte_size).to be <= 100.kilobytes
    end
  end

  # Wraps raw bytes as an uploaded file for the service
  def upload(bytes, content_type = 'image/png')
    file = Tempfile.new(['src', ".#{content_type.split('/').last}"])
    file.binmode
    file.write(bytes)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'src', type: content_type)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/stickers/converter_service_spec.rb`
Expected: FAIL with `uninitialized constant Stickers::ConverterService`.

- [ ] **Step 3: Implement the static path**

Create `app/services/stickers/converter_service.rb`:

```ruby
class Stickers::ConverterService
  TARGET = 512
  MAX_INPUT_BYTES = 5.megabytes
  STATIC_MAX_BYTES = 100.kilobytes
  ANIMATED_MAX_BYTES = 500.kilobytes
  QUALITY_STEPS = [80, 70, 60, 50, 40, 30].freeze

  class InvalidSource < StandardError; end

  def initialize(account:, user:, file: nil, blob: nil)
    @account = account
    @user = user
    @bytes = read_bytes(file, blob)
  end

  def perform
    raise InvalidSource, 'empty source' if @bytes.blank?
    raise InvalidSource, 'source too large' if @bytes.bytesize > MAX_INPUT_BYTES

    webp, animated = build_webp
    sticker = @account.stickers.new(user: @user, animated: animated)
    sticker.file.attach(io: StringIO.new(webp), filename: 'sticker.webp', content_type: 'image/webp')
    sticker.save!
    sticker
  end

  private

  def read_bytes(file, blob)
    return file.read if file.respond_to?(:read)
    return blob.download if blob

    nil
  end

  def build_webp
    pages = page_count
    if pages > 1
      [optimize_animated, true]
    else
      [optimize_static, false]
    end
  rescue Vips::Error => e
    raise InvalidSource, e.message
  end

  def page_count
    img = Vips::Image.new_from_buffer(@bytes, '', access: :sequential, n: -1)
    img.get('n-pages')
  rescue Vips::Error
    1
  end

  def optimize_static
    thumb = Vips::Image.thumbnail_buffer(@bytes, TARGET, height: TARGET, size: :down)
    square = thumb.gravity('centre', TARGET, TARGET, extend: :background, background: [0, 0, 0, 0])
    square = square.colourspace(:srgb) unless square.bands >= 4 # ensure alpha-capable
    encode_within(square, STATIC_MAX_BYTES)
  end

  def encode_within(image, max_bytes, animated: false)
    QUALITY_STEPS.each do |q|
      bytes = image.write_to_buffer('.webp', Q: q, effort: 4)
      return bytes if bytes.bytesize <= max_bytes
    end
    image.write_to_buffer('.webp', Q: QUALITY_STEPS.last, effort: 4)
  end
end
```

- [ ] **Step 4: Run the static test to verify it passes**

Run: `bundle exec rspec spec/services/stickers/converter_service_spec.rb`
Expected: PASS (the `static image` example green).

- [ ] **Step 5: Commit**

```bash
git add app/services/stickers/converter_service.rb spec/services/stickers/converter_service_spec.rb
git commit -m "feat(stickers): converter service for static 512px webp"
```

---

## Task 4: ConverterService — animated webp

> **Highest-risk step.** Animated webp resizing with libvips is fiddly. The test below is the contract; iterate the implementation against it until green. If animation cannot be preserved within the size budget, fall back to the first frame (still a valid sticker).

**Files:**
- Modify: `app/services/stickers/converter_service.rb`
- Test: `spec/services/stickers/converter_service_spec.rb`

- [ ] **Step 1: Add the failing animated test**

Add inside the `RSpec.describe` block in `spec/services/stickers/converter_service_spec.rb`:

```ruby
  describe 'animated image' do
    # 3-frame animated gif strip via libvips (toilet-roll layout + page-height)
    def animated_gif_bytes
      frame = Vips::Image.black(120, 120).add([0, 255, 0]).cast(:uchar).copy(interpretation: :srgb)
      strip = Vips::Image.arrayjoin([frame, frame, frame], across: 1)
      strip = strip.copy
      strip.set_type(Vips::BlobType::GINT, 'page-height', 120)
      strip.set_type(Vips::BlobType::GINT, 'n-pages', 3)
      strip.write_to_buffer('.gif')
    end

    it 'produces an animated webp under 500KB preserving multiple frames' do
      sticker = described_class.new(account: account, user: user, file: upload(animated_gif_bytes, 'image/gif')).perform

      expect(sticker.animated).to be(true)
      expect(sticker.file.content_type).to eq('image/webp')
      out = Vips::Image.new_from_buffer(sticker.file.download, '', n: -1)
      expect(out.get('n-pages')).to be > 1
      expect(sticker.file.byte_size).to be <= 500.kilobytes
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/stickers/converter_service_spec.rb -e "animated"`
Expected: FAIL (currently `optimize_animated` is not defined / NoMethodError).

- [ ] **Step 3: Implement `optimize_animated`**

Add these private methods to `app/services/stickers/converter_service.rb`:

```ruby
  def optimize_animated
    # libvips thumbnail is animation-aware when the loader is told to read all
    # pages via option_string 'n=-1'. The result keeps the page/animation metadata.
    thumb = Vips::Image.thumbnail_buffer(@bytes, TARGET, height: TARGET, size: :down, option_string: 'n=-1')
    encode_within(thumb, ANIMATED_MAX_BYTES, animated: true)
  rescue Vips::Error
    # Fallback: first frame as a static sticker (still valid for WhatsApp).
    optimize_static
  end
```

> If the produced webp is not square 512×512, that is acceptable for animated stickers in this MVP (WhatsApp accepts the aspect from the thumbnail). Do **not** add per-frame gravity/padding unless a later test requires it — keep YAGNI.

- [ ] **Step 4: Run the animated test to verify it passes**

Run: `bundle exec rspec spec/services/stickers/converter_service_spec.rb`
Expected: PASS (both static and animated examples). If `n-pages` is 1, iterate: confirm libvips version supports `option_string`, and that the input truly has multiple pages.

- [ ] **Step 5: Commit**

```bash
git add app/services/stickers/converter_service.rb spec/services/stickers/converter_service_spec.rb
git commit -m "feat(stickers): preserve animation when converting to webp"
```

---

## Task 5: WhatsApp Cloud — send_sticker_message + branch

**Files:**
- Modify: `app/services/whatsapp/providers/whatsapp_cloud_service.rb`
- Test: `spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb` (inside the existing top-level describe; reuse existing `let(:whatsapp_channel)` / `let(:message)` helpers — read the file first to match its setup):

```ruby
  describe '#send_message with a sticker' do
    let(:sticker_message) do
      create(:message, message_type: :outgoing, content_type: 'sticker',
                       content: nil, inbox: whatsapp_channel.inbox, conversation: conversation).tap do |m|
        m.attachments.create!(account_id: m.account_id, file_type: :image,
                              file: { io: StringIO.new(Vips::Image.black(8, 8).write_to_buffer('.webp')),
                                      filename: 'sticker.webp', content_type: 'image/webp' })
      end
    end

    it 'posts a sticker type message with a media link' do
      stub = stub_request(:post, "#{api_base_path}/messages")
             .to_return(status: 200, body: { messages: [{ id: 'wamid.sticker' }] }.to_json,
                        headers: { 'content-type' => 'application/json' })

      service.send_message('+5511999999999', sticker_message)

      expect(stub).to have_been_requested
      expect(WebMock).to have_requested(:post, "#{api_base_path}/messages")
        .with { |req| body = JSON.parse(req.body); body['type'] == 'sticker' && body['sticker']['link'].present? }
    end
  end
```

> Match `api_base_path`, `service`, `conversation`, and `whatsapp_channel` to the names already used in this spec file. Read it first (`sed -n '1,60p'`).

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb -e "sticker"`
Expected: FAIL — the request body has `type: 'image'` (current attachment branch), not `type: 'sticker'`.

- [ ] **Step 3: Add the branch and the method**

In `app/services/whatsapp/providers/whatsapp_cloud_service.rb`, change the start of `send_message` so the sticker branch runs **before** the generic attachment branch:

```ruby
    if message.content_type == 'sticker' && message.attachments.present?
      send_sticker_message(phone_number, message)
    elsif message.attachments.present?
      send_attachment_message(phone_number, message)
```

(Insert the first two lines immediately before the existing `if message.attachments.present?` line, converting that `if` to `elsif`.)

Then add this method near `send_attachment_message`:

```ruby
  def send_sticker_message(phone_number, message)
    attachment = message.attachments.first
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        type: 'sticker',
        sticker: { link: attachment.download_url }
      }.to_json
    )

    process_response(response, message)
  end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb -e "sticker"`
Expected: PASS.

- [ ] **Step 5: Run rubocop + full file spec**

Run: `bundle exec rubocop app/services/whatsapp/providers/whatsapp_cloud_service.rb && bundle exec rspec spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb`
Expected: no offenses; all examples pass (no regression to attachment/text/template branches).

- [ ] **Step 6: Commit**

```bash
git add app/services/whatsapp/providers/whatsapp_cloud_service.rb spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb
git commit -m "feat(stickers): send native WhatsApp sticker via cloud provider"
```

---

## Task 6: Stickers controller + routes

**Files:**
- Create: `app/controllers/api/v1/accounts/stickers_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/controllers/api/v1/accounts/stickers_controller_spec.rb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, inside the `resources :accounts ... do` → account members block (next to other account-scoped resources like `resources :macros`), add:

```ruby
        resources :stickers, only: [:index, :create, :destroy] do
          member do
            post :send_sticker
          end
        end
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/controllers/api/v1/accounts/stickers_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Stickers API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def png_upload
    bytes = Vips::Image.black(300, 300).add([0, 0, 255]).cast(:uchar).copy(interpretation: :srgb).write_to_buffer('.png')
    file = Tempfile.new(['s', '.png']); file.binmode; file.write(bytes); file.rewind
    Rack::Test::UploadedFile.new(file.path, 'image/png')
  end

  describe 'POST /api/v1/accounts/{account}/stickers' do
    it 'creates a sticker from an uploaded image' do
      expect do
        post "/api/v1/accounts/#{account.id}/stickers",
             params: { file: png_upload }, headers: agent.create_new_auth_token
      end.to change(Sticker, :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /api/v1/accounts/{account}/stickers/{id}/send_sticker' do
    let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
    let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
    let(:sticker) { Stickers::ConverterService.new(account: account, user: agent, file: png_upload).perform }

    it 'creates an outgoing sticker message in the conversation' do
      expect do
        post "/api/v1/accounts/#{account.id}/stickers/#{sticker.id}/send_sticker",
             params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token
      end.to change { conversation.messages.where(content_type: 'sticker').count }.by(1)
      expect(response).to have_http_status(:success)
    end
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/stickers_controller_spec.rb`
Expected: FAIL — routing error / `uninitialized constant` for the controller.

- [ ] **Step 4: Implement the controller**

Create `app/controllers/api/v1/accounts/stickers_controller.rb`:

```ruby
class Api::V1::Accounts::StickersController < Api::V1::Accounts::BaseController
  before_action :fetch_sticker, only: [:destroy, :send_sticker]

  def index
    authorize Sticker
    @stickers = if ActiveModel::Type::Boolean.new.cast(params[:recent])
                  Sticker.recent_for(Current.account, Current.user)
                else
                  Current.account.stickers.order(created_at: :desc)
                end
  end

  def create
    authorize Sticker
    @sticker = build_sticker
    render json: serialize(@sticker)
  rescue Stickers::ConverterService::InvalidSource => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    authorize @sticker
    @sticker.destroy!
    head :ok
  end

  def send_sticker
    authorize @sticker, :send_sticker?
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    message = Messages::MessageBuilder.new(
      Current.user, conversation,
      { message_type: 'outgoing', content_type: 'sticker', attachments: [@sticker.file.blob.signed_id] }
    ).perform
    Sticker.touch_recent(Current.user, @sticker.id)
    render json: { id: message.id }
  end

  private

  def fetch_sticker
    @sticker = Current.account.stickers.find(params[:id])
  end

  def build_sticker
    if params[:source_attachment_id].present?
      attachment = Current.account.messages.joins(:attachments)
                          .merge(Attachment.where(id: params[:source_attachment_id])).first&.attachments&.find(params[:source_attachment_id])
      raise Stickers::ConverterService::InvalidSource, 'attachment not found' if attachment.blank?

      Stickers::ConverterService.new(account: Current.account, user: Current.user, blob: attachment.file.blob).perform
    else
      Stickers::ConverterService.new(account: Current.account, user: Current.user, file: params[:file]).perform
    end
  end

  def serialize(sticker)
    { id: sticker.id, animated: sticker.animated, url: url_for(sticker.file) }
  end
end
```

> Confirm the base controller class name by reading a sibling controller (e.g. `app/controllers/api/v1/accounts/macros_controller.rb`) — match its superclass and how it accesses `Current.account` / `Current.user`. Adjust `serialize`'s `url_for` if siblings use a helper for attachment URLs.

- [ ] **Step 5: Add the index view (jbuilder) if siblings use views**

If sibling controllers render via jbuilder (check `app/views/api/v1/accounts/macros/`), create `app/views/api/v1/accounts/stickers/index.json.jbuilder`:

```ruby
json.array! @stickers do |sticker|
  json.id sticker.id
  json.animated sticker.animated
  json.url url_for(sticker.file)
end
```

Otherwise, make `index` render JSON inline like `create`.

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/stickers_controller_spec.rb`
Expected: PASS (both examples). Fix the base-controller superclass / `Current` accessors if the first run errors.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/accounts/stickers_controller.rb config/routes.rb spec/controllers/api/v1/accounts/stickers_controller_spec.rb app/views/api/v1/accounts/stickers 2>/dev/null
git commit -m "feat(stickers): stickers controller (list, create, delete, send)"
```

---

## Task 7: Frontend API client + composable

**Files:**
- Create: `app/javascript/dashboard/api/stickers.js`
- Create: `app/javascript/dashboard/composables/useStickers.js`

- [ ] **Step 1: Create the API client**

Create `app/javascript/dashboard/api/stickers.js`:

```js
/* global axios */
import ApiClient from './ApiClient';

class StickersAPI extends ApiClient {
  constructor() {
    super('stickers', { accountScoped: true });
  }

  getRecent() {
    return axios.get(this.url, { params: { recent: true } });
  }

  create(formData) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  createFromAttachment(sourceAttachmentId) {
    return axios.post(this.url, { source_attachment_id: sourceAttachmentId });
  }

  send({ stickerId, conversationId }) {
    return axios.post(`${this.url}/${stickerId}/send_sticker`, {
      conversation_id: conversationId,
    });
  }
}

export default new StickersAPI();
```

- [ ] **Step 2: Create the composable**

Create `app/javascript/dashboard/composables/useStickers.js`:

```js
import { ref } from 'vue';
import StickersAPI from 'dashboard/api/stickers';
import { useAlert } from 'dashboard/composables';

export function useStickers() {
  const stickers = ref([]);
  const recent = ref([]);
  const isLoading = ref(false);

  const fetchLibrary = async () => {
    isLoading.value = true;
    try {
      const [{ data: all }, { data: recents }] = await Promise.all([
        StickersAPI.get(),
        StickersAPI.getRecent(),
      ]);
      stickers.value = all;
      recent.value = recents;
    } finally {
      isLoading.value = false;
    }
  };

  const createFromFile = async file => {
    const formData = new FormData();
    formData.append('file', file);
    const { data } = await StickersAPI.create(formData);
    stickers.value = [data, ...stickers.value];
    return data;
  };

  const createFromAttachment = async attachmentId => {
    const { data } = await StickersAPI.createFromAttachment(attachmentId);
    stickers.value = [data, ...stickers.value];
    return data;
  };

  const remove = async id => {
    await StickersAPI.destroy(id);
    stickers.value = stickers.value.filter(s => s.id !== id);
    recent.value = recent.value.filter(s => s.id !== id);
  };

  const send = async ({ stickerId, conversationId }) => {
    try {
      await StickersAPI.send({ stickerId, conversationId });
    } catch (e) {
      useAlert(e?.response?.data?.error);
      throw e;
    }
  };

  return {
    stickers,
    recent,
    isLoading,
    fetchLibrary,
    createFromFile,
    createFromAttachment,
    remove,
    send,
  };
}
```

- [ ] **Step 3: Lint**

Run: `pnpm eslint app/javascript/dashboard/api/stickers.js app/javascript/dashboard/composables/useStickers.js`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/api/stickers.js app/javascript/dashboard/composables/useStickers.js
git commit -m "feat(stickers): frontend api client and useStickers composable"
```

---

## Task 8: Sticker bubble + dispatcher registration

**Files:**
- Create: `app/javascript/dashboard/components-next/message/bubbles/Sticker.vue`
- Modify: `app/javascript/dashboard/components-next/message/Message.vue`

- [ ] **Step 1: Create the bubble**

Create `app/javascript/dashboard/components-next/message/bubbles/Sticker.vue`:

```vue
<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../provider.js';

const { attachments } = useMessageContext();

const url = computed(() => attachments.value?.[0]?.dataUrl || attachments.value?.[0]?.thumbUrl);
</script>

<template>
  <img
    v-if="url"
    :src="url"
    alt=""
    class="object-contain w-32 h-32 max-w-full bg-transparent rounded-lg"
  />
</template>
```

> Verify the context accessor: open `app/javascript/dashboard/components-next/message/provider.js` and use whatever it exports (e.g. `useMessageContext`) and the exact attachment field names (`dataUrl`/`thumbUrl`) the other bubbles use (compare `bubbles/Image.vue`). Match those names.

- [ ] **Step 2: Register in the dispatcher**

In `app/javascript/dashboard/components-next/message/Message.vue`:

(a) Add the import next to the other bubble imports (around line 48):

```js
import StickerBubble from './bubbles/Sticker.vue';
```

(b) In the `componentToRender` computed, add this branch near the top (before the attachment-based checks, after the CSAT/Form/VoiceCall checks ~line 322):

```js
  if (props.contentType === CONTENT_TYPES.STICKER) {
    return StickerBubble;
  }
```

- [ ] **Step 3: Lint**

Run: `pnpm eslint app/javascript/dashboard/components-next/message/bubbles/Sticker.vue app/javascript/dashboard/components-next/message/Message.vue`
Expected: no errors.

- [ ] **Step 4: Manual verification (deferred to end-to-end)**

This bubble is verified visually in Task 12's manual check (send a sticker, confirm it renders borderless at sticker size). No unit test (project convention: avoid UI specs).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/components-next/message/bubbles/Sticker.vue app/javascript/dashboard/components-next/message/Message.vue
git commit -m "feat(stickers): render sticker messages with a dedicated bubble"
```

---

## Task 9: Desktop picker + composer button

**Files:**
- Create: `app/javascript/dashboard/components/widgets/conversation/StickerPicker/StickerPicker.vue`
- Modify: `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue`
- Modify: `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`

- [ ] **Step 1: Create the picker**

Create `app/javascript/dashboard/components/widgets/conversation/StickerPicker/StickerPicker.vue`:

```vue
<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStickers } from 'dashboard/composables/useStickers';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const {
  stickers,
  recent,
  isLoading,
  fetchLibrary,
  createFromFile,
  send,
} = useStickers();

const fileInput = ref(null);

onMounted(fetchLibrary);

const onSend = async sticker => {
  await send({ stickerId: sticker.id, conversationId: props.conversationId });
  emit('close');
};

const onPick = () => fileInput.value?.click();

const onFile = async e => {
  const file = e.target.files?.[0];
  if (file) await createFromFile(file);
  e.target.value = '';
};
</script>

<template>
  <div
    class="flex flex-col w-80 max-h-96 bg-n-background border border-n-weak rounded-xl shadow-lg overflow-hidden"
  >
    <div class="flex items-center justify-between px-3 py-2 border-b border-n-weak">
      <span class="text-sm font-medium text-n-slate-12">{{ t('STICKERS.TITLE') }}</span>
      <button class="text-xs text-n-brand" @click="onPick">{{ t('STICKERS.ADD') }}</button>
    </div>
    <div v-if="isLoading" class="p-4 text-center text-sm text-n-slate-11">{{ t('STICKERS.LOADING') }}</div>
    <div v-else class="grid grid-cols-4 gap-2 p-3 overflow-y-auto">
      <button
        v-for="sticker in [...recent, ...stickers]"
        :key="sticker.id"
        class="aspect-square flex items-center justify-center rounded-lg hover:bg-n-alpha-2"
        @click="onSend(sticker)"
      >
        <img :src="sticker.url" alt="" class="object-contain w-full h-full" />
      </button>
    </div>
    <input ref="fileInput" type="file" accept="image/*" class="hidden" @change="onFile" />
  </div>
</template>
```

- [ ] **Step 2: Add the desktop button**

In `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue`, add a `NextButton` in the toolbar (near the WhatsApp template button at line ~365), shown only on WhatsApp channels (`isAWhatsAppChannel` exists via `inboxMixin`):

```html
      <NextButton
        v-if="isAWhatsAppChannel && !isNote"
        v-tooltip.top-end="$t('STICKERS.TITLE')"
        icon="i-ph-sticker"
        slate
        faded
        xs
        @click="$emit('toggleStickerPicker')"
      />
```

Add `'toggleStickerPicker'` to the component's `emits` array (find the existing `emits:` declaration; if buttons use `$emit` with declared emits, append the name).

> Confirm `isAWhatsAppChannel` is the exact mixin getter (search `rg -n "isAWhatsAppChannel|isAWhatsApp" shared/mixins/inboxMixin.js`). Use whatever WhatsApp guard `selectWhatsappTemplate` already relies on in this file.

- [ ] **Step 3: Host the picker in ReplyBox**

In `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`:

(a) Import + register `StickerPicker` and add local state `showStickerPicker = ref(false)` (match the file's API — it may be Options or Composition; mirror how `showWhatsappTemplates`-style modals are toggled).

(b) Listen to the new event from `ReplyBottomPanel`: `@toggle-sticker-picker="showStickerPicker = !showStickerPicker"`.

(c) Render the picker as a popover above the bottom panel when `showStickerPicker`:

```html
    <StickerPicker
      v-if="showStickerPicker"
      :conversation-id="currentChat.id"
      class="absolute bottom-16 left-3 z-50"
      @close="showStickerPicker = false"
    />
```

> Place it inside the composer's relatively-positioned wrapper. Confirm `currentChat`/`conversationId` accessor name used elsewhere in ReplyBox.

- [ ] **Step 4: Lint**

Run: `pnpm eslint app/javascript/dashboard/components/widgets/conversation/StickerPicker/StickerPicker.vue app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/components/widgets/conversation/StickerPicker app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue
git commit -m "feat(stickers): desktop sticker picker and composer button"
```

---

## Task 10: Mobile (PWA) picker + composer button

**Files:**
- Create: `app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue`
- Modify: `app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue`

- [ ] **Step 1: Create the mobile sheet**

Create `app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue`:

```vue
<script setup>
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStickers } from 'dashboard/composables/useStickers';
import MobileBottomSheet from './MobileBottomSheet.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close', 'pick-image']);

const { t } = useI18n();
const { stickers, recent, fetchLibrary, send } = useStickers();

onMounted(fetchLibrary);

const onSend = async sticker => {
  await send({ stickerId: sticker.id, conversationId: props.conversationId });
  emit('close');
};
</script>

<template>
  <MobileBottomSheet :open="open" :title="t('STICKERS.TITLE')" @close="emit('close')">
    <div class="grid grid-cols-4 gap-2 p-3 max-h-[50vh] overflow-y-auto">
      <button
        class="aspect-square flex items-center justify-center rounded-lg border border-dashed border-n-weak text-n-slate-11"
        :aria-label="t('STICKERS.ADD')"
        @click="emit('pick-image')"
      >
        <span class="i-lucide-plus text-xl" aria-hidden="true" />
      </button>
      <button
        v-for="sticker in [...recent, ...stickers]"
        :key="sticker.id"
        class="aspect-square flex items-center justify-center rounded-lg active:bg-n-alpha-2"
        @click="onSend(sticker)"
      >
        <img :src="sticker.url" alt="" class="object-contain w-full h-full" />
      </button>
    </div>
  </MobileBottomSheet>
</template>
```

> Confirm `MobileBottomSheet.vue`'s prop/slot/event contract (`open`, `title`, `@close`) by reading it; adapt prop names to match exactly.

- [ ] **Step 2: Add the sticker button to MobileReplyBox**

In `app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue`:

(a) Import the sheet and add state:

```js
import MobileStickerSheet from './MobileStickerSheet.vue';
// ...
const showStickerSheet = ref(false);
const showStickers = computed(() => !effectivePrivate.value && !isEditorDisabled.value && channelType.value === 'Channel::Whatsapp');
```

(b) Add a sticker button inside the input pill, just before the lock toggle (so it sits inside the rounded field like WhatsApp). After the `<textarea>` and before the lock `<button>` (around line 687):

```html
        <!-- Sticker picker -->
        <button
          v-if="showStickers"
          v-haptic-tap
          class="flex items-center justify-center w-7 h-7 flex-shrink-0 ml-1 text-n-slate-9"
          :aria-label="t('STICKERS.TITLE')"
          @click="showStickerSheet = true"
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M15.5 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h9l7-7V5a2 2 0 0 0-2-2z" />
            <path d="M14 21v-5a2 2 0 0 1 2-2h5" />
          </svg>
        </button>
```

(c) Add the sheet near the other sheets at the end of the template (after `MobileActionPickerSheet`):

```html
    <MobileStickerSheet
      :open="showStickerSheet"
      :conversation-id="currentChat?.id"
      @close="showStickerSheet = false"
      @pick-image="onAttachClick"
    />
```

> Reuse the existing `onAttachClick`/`onCameraClick` + `onFileChange` flow for "create from image/camera". When a file is picked for a sticker, route it through `createFromFile` (from `useStickers`) instead of attaching as a normal message — add a small `creatingSticker` flag set when `@pick-image` fires, and branch in `onFileChange`. Keep this minimal.

- [ ] **Step 3: Lint**

Run: `pnpm eslint app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue
git commit -m "feat(stickers): mobile sticker sheet and composer button"
```

---

## Task 11: "Save as sticker" on received stickers

**Files:**
- Modify: `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue`
- Modify: `app/javascript/dashboard/components-next/mobile/MobileMessageContextMenu.vue`

- [ ] **Step 1: Add a menu entry (desktop)**

In `MessageContextMenu.vue`, add a menu item shown when the message has an image attachment, that calls the composable's `createFromAttachment(attachmentId)` and shows a success alert. Follow the file's existing item pattern (each item is a `<MenuItem>`/button emitting an action). Wire it to:

```js
import { useStickers } from 'dashboard/composables/useStickers';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
// ...
const { createFromAttachment } = useStickers();
const { t } = useI18n();
const saveAsSticker = async attachmentId => {
  try {
    await createFromAttachment(attachmentId);
    useAlert(t('STICKERS.SAVED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('STICKERS.SAVE_FAILED'));
  }
};
```

Show the item only when `message.attachments?.[0]?.file_type === 'image'`.

- [ ] **Step 2: Mirror on mobile context menu**

Add the same "Save as sticker" option to `MobileMessageContextMenu.vue`, matching its existing item structure, calling the same `createFromAttachment` flow.

- [ ] **Step 3: Lint**

Run: `pnpm eslint app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue app/javascript/dashboard/components-next/mobile/MobileMessageContextMenu.vue`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue app/javascript/dashboard/components-next/mobile/MobileMessageContextMenu.vue
git commit -m "feat(stickers): save a received sticker/image to the library"
```

---

## Task 12: i18n, docs, manual end-to-end verification

**Files:**
- Modify: `app/javascript/dashboard/i18n/locale/en/conversation.json` (or the appropriate dashboard bundle; mirror to `pt`, `pt_BR`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt,pt_BR}/mobile.json`
- Modify: `config/locales/en.yml` (only if a backend string is user-facing — error messages are returned raw, so likely none)
- Modify: `chatwitdocs/Chatwoot-Chatwit-mobile.md`, `chatwitdocs/migration-etapa3-stickers.md`, `CLAUDE.md`

- [ ] **Step 1: Add i18n keys**

Add a `STICKERS` block to `en`, `pt`, `pt_BR` dashboard bundles (put it where component strings live; check which bundle `useI18n` resolves — likely `conversation.json` or a new `stickers.json` registered in the locale index). Keys:

```json
"STICKERS": {
  "TITLE": "Stickers",
  "ADD": "Add",
  "LOADING": "Loading…",
  "SAVED": "Sticker saved",
  "SAVE_FAILED": "Could not save sticker"
}
```

pt / pt_BR values: `TITLE: "Figurinhas"`, `ADD: "Adicionar"`, `LOADING: "Carregando…"`, `SAVED: "Figurinha salva"`, `SAVE_FAILED: "Não foi possível salvar a figurinha"`.

Mirror `TITLE`/`ADD` into the three `mobile.json` bundles under the existing `MOBILE` namespace (e.g. `MOBILE.STICKERS.TITLE`) and reference those keys in mobile components instead of the dashboard keys, to match the mobile module convention.

- [ ] **Step 2: Verify no missing-key warnings**

Run: `pnpm eslint app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue` and grep the keys exist:
```bash
grep -r "\"STICKERS\"" app/javascript/dashboard/i18n/locale/{en,pt,pt_BR} ; grep -r "STICKERS" app/javascript/dashboard/i18n/locale/{en,pt,pt_BR}/mobile.json
```
Expected: keys present in all bundles.

- [ ] **Step 3: Update docs**

- `chatwitdocs/Chatwoot-Chatwit-mobile.md`: add a changelog entry (sticker button + sheet in `MobileReplyBox`, reusing `useStickers`).
- Create `chatwitdocs/migration-etapa3-stickers.md`: rotas, services (`ConverterService`, `send_sticker_message`), fluxo de envio nativo, criação/salvamento, decisão de link vs upload.
- `CLAUDE.md`: mark Etapa 3 (Stickers) as **Completa** with a pointer to the new doc.

- [ ] **Step 4: Backend regression + lint**

Run:
```bash
bundle exec rspec spec/services/stickers/converter_service_spec.rb spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb spec/controllers/api/v1/accounts/stickers_controller_spec.rb
bundle exec rubocop app/services/stickers app/controllers/api/v1/accounts/stickers_controller.rb app/models/sticker.rb app/policies/sticker_policy.rb app/services/whatsapp/providers/whatsapp_cloud_service.rb
```
Expected: all specs pass; no rubocop offenses.

- [ ] **Step 5: Manual end-to-end (desktop + mobile)**

Start the app (`overmind start -f Procfile.dev`) and, against a WhatsApp Cloud inbox:
1. Desktop: open a WhatsApp conversation → sticker button visible → open picker → "Add" → choose an image → it appears → click it → sticker sends and renders borderless at sticker size; arrives on WhatsApp as a real sticker.
2. Desktop: convert/send an **animated** gif → arrives animated.
3. Desktop: right-click a **received** sticker/image → "Save as sticker" → appears in library.
4. Mobile (viewport < 768px): sticker button inside the input pill → sheet opens → send works; "+" opens image/camera and creates a sticker.
5. Confirm **desktop composer is otherwise unchanged** and **no sticker UI leaks at ≥768px** in mobile components.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/i18n chatwitdocs CLAUDE.md
git commit -m "feat(stickers): i18n, docs, and mark migration etapa 3 complete"
```

---

## Self-Review

**Spec coverage:**
- Biblioteca por conta + recents → Task 1 (model, `recent_for`, `touch_recent`). ✓
- Criar de imagem/câmera → Tasks 7 (composable), 9 (desktop), 10 (mobile). ✓
- Salvar de figurinha recebida → Task 11. ✓
- Conversão estática + animada (libvips) → Tasks 3, 4. ✓
- Envio nativo WhatsApp Cloud (`type: sticker`) → Task 5. ✓
- Endpoints (index/create/destroy/send) → Task 6. ✓
- Bubble → Task 8. ✓
- Botão desktop + mobile → Tasks 9, 10. ✓
- Isolamento + i18n + docs → Tasks 10, 12. ✓
- Apagar = criador/admin → Task 2 policy. ✓

**Placeholder scan:** Verification "confirm sibling/contract" notes are intentional grounding checks, not deferred work — each task ships complete code. No TBD/TODO left.

**Type/name consistency:** `ConverterService.new(account:, user:, file:/blob:)` + `#perform` returning a `Sticker` is used consistently (Tasks 3, 4, 6). `Sticker.touch_recent`/`recent_for(account, user)` consistent (Tasks 1, 6). `send_sticker` route/action name consistent (Tasks 6 routes ↔ controller ↔ api client `send`). API client methods (`get`, `getRecent`, `create`, `createFromAttachment`, `send`, `destroy`) match composable usage (Task 7) and component calls (Tasks 9–11). `content_type: 'sticker'` consistent (Tasks 5, 6, 8).

**Known risk:** Task 4 animated webp encoding — gated by its test; static fallback built in.
