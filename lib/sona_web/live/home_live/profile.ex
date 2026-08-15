defmodule SonaWeb.HomeLive.Profile do
  @moduledoc """
  The Profile tab: identity as read-only operator-managed facts, and the
  settings a staff member controls themselves.
  """
  use SonaWeb, :html

  import SonaWeb.HomeLive.UI

  alias Sona.Coordination.StaffMember

  attr :current_staff, :map, required: true

  def profile_view(assigns) do
    ~H"""
    <section class="page-heading compact-heading">
      <div>
        <p class="date-line">{gettext("Your workspace")}</p>
        <h1>{gettext("Profile")}</h1>
        <p class="heading-subtitle">
          {gettext("Keep your role and language ready for every handoff.")}
        </p>
      </div>
    </section>
    <section class="profile-card">
      <div class="profile-hero">
        <span class={"avatar large #{avatar_palette(@current_staff.name)}"}>
          {initials(@current_staff.name)}
        </span>
        <div>
          <h2>{@current_staff.name}</h2>
          <p>{@current_staff.role} · {@current_staff.department}</p>
        </div>
      </div>
      <div class="profile-fields">
        <div>
          <span class="eyebrow">{gettext("ROLE")}</span>
          <strong>{@current_staff.role}</strong>
        </div>
        <div>
          <span class="eyebrow">{gettext("DEPARTMENT")}</span>
          <strong>{@current_staff.department}</strong>
        </div>
        <div>
          <span class="eyebrow">{gettext("CURRENT PROPERTY")}</span>
          <strong>The Lark Hotel</strong>
        </div>
      </div>
      <p class="profile-note">
        {gettext("Your role, department and property are managed by your hotel's operations team.")}
      </p>
    </section>

    <section class="settings-card">
      <div class="section-heading compact">
        <div>
          <span class="section-kicker">{gettext("YOUR SETTINGS")}</span>
          <h2>{gettext("How you use Sona")}</h2>
        </div>
      </div>

      <form phx-submit="save_settings" class="settings-form">
        <label class="settings-field">
          <span class="settings-label">{gettext("Preferred language")}</span>
          <span class="settings-hint">
            {gettext("Changes updates, tasks and responses across the whole app.")}
          </span>
          <select name="language">
            <option
              :for={language <- StaffMember.languages()}
              value={language}
              selected={language == @current_staff.language}
            >
              {language_label(language)}
            </option>
          </select>
        </label>

        <fieldset class="settings-field">
          <legend class="settings-label">{gettext("Notifications")}</legend>
          <input type="hidden" name="notify_in_app" value="false" />
          <label class="settings-toggle">
            <input
              type="checkbox"
              name="notify_in_app"
              value="true"
              checked={@current_staff.notify_in_app}
            />
            <span>
              <strong>{gettext("In-app alerts")}</strong>
              <small>{gettext("Urgent updates and replies appear in your activity feed.")}</small>
            </span>
          </label>
          <label class="settings-toggle disabled">
            <input type="checkbox" disabled />
            <span>
              <strong>{gettext("Push and SMS")}</strong>
              <small>{gettext("Not available in this prototype — no messages are sent.")}</small>
            </span>
          </label>
        </fieldset>

        <button class="primary-button">
          <.icon name="check" /> {gettext("Save settings")}
        </button>
      </form>
    </section>
    """
  end
end
