defmodule Slack.Sends do
  @moduledoc "Utility functions for sending slack messages"
  alias Slack.Lookups

  @doc """
  Sends `text` to `channel` for the given `slack` connection.  `channel` can be
  a string in the format of `"#CHANNEL_NAME"`, `"@USER_NAME"`, or any ID that
  Slack understands.

  NOTE: Referencing `"@USER_NAME"` is deprecated, and should not be used.
  For more information see https://api.slack.com/changelog/2017-09-the-one-about-usernames
  """

  def send_message(text, channel, slack, thread_ts \\ nil)

  def send_message(text, channel = "#" <> channel_name, slack, thread_ts) do
    channel_id = Lookups.lookup_channel_id(channel, slack)

    if channel_id do
      send_message(text, channel_id, slack, thread_ts)
    else
      raise ArgumentError, "channel ##{channel_name} not found"
    end
  end

  def send_message(text, user_id = "U" <> _user_id, slack, thread_ts) do
    send_message_to_user(text, user_id, slack, thread_ts)
  end

  def send_message(text, user_id = "W" <> _user_id, slack, thread_ts) do
    send_message_to_user(text, user_id, slack, thread_ts)
  end

  def send_message(text, user = "@" <> _user_name, slack, thread_ts) do
    user_id = Lookups.lookup_user_id(user, slack)
    send_message(text, user_id, slack, thread_ts)
  end

  def send_message(text, channel, slack, nil) do
    send_message(
      %{
        type: "message",
        text: text,
        channel: channel
      },
      slack
    )
  end

  def send_message(text, channel, slack, thread_ts) do
    send_message(
      %{
        type: "message",
        text: text,
        channel: channel,
        thread_ts: thread_ts
      },
      slack
    )
  end

  def send_message(message, slack) do
    message
    |> Poison.encode!()
    |> send_raw(slack)
  end

  @doc """
  Notifies Slack that the current user is typing in `channel`.
  """
  def indicate_typing(channel, slack) do
    %{
      type: "typing",
      channel: channel
    }
    |> Poison.encode!()
    |> send_raw(slack)
  end

  @doc """
  Notifies slack that the current `slack` user is typing in `channel`.
  """
  def send_ping(data \\ %{}, slack) do
    %{
      type: "ping"
    }
    |> Map.merge(Map.new(data))
    |> Poison.encode!()
    |> send_raw(slack)
  end

  @doc """
  Subscribe to presence notifications for the user IDs in `ids`.
  """
  def subscribe_presence(ids \\ [], slack) do
    %{
      type: "presence_sub",
      ids: ids
    }
    |> Poison.encode!()
    |> send_raw(slack)
  end

  @doc """
  Sends raw JSON to a given socket.
  """
  def send_raw(json, %{process: pid, client: client}) do
    client.cast(pid, {:text, json})
  end

  defp send_message_to_user(text, user_id, slack, thread_ts) do
    direct_message_id = Lookups.lookup_direct_message_id(user_id, slack)

    if direct_message_id do
      send_message(text, direct_message_id, slack, thread_ts)
    else
      open_im_channel(
        slack.token,
        user_id,
        fn id -> send_message(text, id, slack, thread_ts) end,
        fn reason -> reason end
      )
    end
  end

  defp open_im_channel(token, user_id, on_success, on_error) do
    im_open =
      with url <- Application.get_env(:slack, :url, "https://slack.com") <> "/api/im.open",
           headers <- {:form, [token: token, user: user_id]},
           options <- Application.get_env(:slack, :web_http_client_opts, []) do
        HTTPoison.post(url, headers, options)
      end

    case im_open do
      {:ok, response} ->
        case Poison.Parser.parse!(response.body, keys: :atoms) do
          %{ok: true, channel: %{id: id}} -> on_success.(id)
          e = %{error: _error_message} -> on_error.(e)
        end

      {:error, reason} ->
        on_error.(reason)
    end
  end
end
