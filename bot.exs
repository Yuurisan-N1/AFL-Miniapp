Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule AFLMining do
  @moduledoc false

  @my_project "AFL Miniapp"
  @base_url "https://afl.up.railway.app"
  @token "AFL"

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[91m"
  @green "\e[92m"
  @yellow "\e[93m"

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    accounts = load_lines("data.txt")

    if accounts == [] do
      red("File data.txt is empty, please add your initData entries")
      System.halt(1)
    end

    proxies = load_lines("proxy.txt")
    settings = load_settings()

    loop(accounts, proxies, settings, 1)
  end

  defp loop(accounts, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    accounts
    |> Enum.with_index()
    |> Enum.each(fn {line, index} ->
      if index > 0, do: IO.puts("")

      proxy = proxy_for(proxies, index)

      case proxy do
        nil -> yellow("Running without proxy for this account")
        entry -> yellow("Using proxy #{mask_proxy(entry)}")
      end

      try do
        process_account(line, index + 1, proxy)
      rescue
        _error ->
          red("Account #{index + 1} was skipped after an error")
      end
    end)

    yellow("All accounts processed for cycle number #{cycle}")

    countdown(sleep_seconds(settings), "Next cycle starts in")

    Banner.show_banner(@my_project)

    loop(accounts, proxies, settings, cycle + 1)
  end

  defp process_account(line, label, proxy) do
    case init_data_of(line) do
      {:ok, init, id, profile} ->
        state = %{
          init: init,
          id: id,
          label: label,
          username: get(profile, "username", ""),
          first_name: get(profile, "firstName", "")
        }

        case fetch_user(state, proxy) do
          {:ok, snapshot} ->
            user = get(snapshot, "user", %{})
            handle = shorten(clean_text(get(user, "username", state.first_name), "account"), "account", 18)
            pool = number(get(user, "poolWallet", 0))

            state = Map.put(state, :handle, handle)

            green("Signed in #{handle} with #{amount(pool)} #{@token}")

            state
            |> process_tasks(snapshot, proxy)
            |> process_referrals(user, proxy)
            |> process_mining(snapshot, proxy)

          {:error, reason} ->
            red("Account #{label} was refused with #{short_reason(reason)}")
        end

      :error ->
        red("Account #{label} line has no usable initData")
    end
  end

  defp process_tasks(state, snapshot, proxy) do
    case call_get("/api/v2/tasks/list", state, proxy) do
      {:ok, data} ->
        done = get(get(snapshot, "user", %{}), "completedTaskIds", []) |> List.wrap()

        pending =
          get(data, "tasks", [])
          |> List.wrap()
          |> Enum.reject(fn task ->
            truthy(get(task, "isCompleted", false)) or
              get(task, "isActive", true) == false or
              Enum.member?(done, get(task, "id", ""))
          end)

        if pending == [] do
          yellow("No claimable task is left for this account")
        else
          Enum.each(pending, fn task -> claim_task(state, task, proxy) end)
        end

      {:error, reason} ->
        yellow("Task list was refused with #{short_reason(reason)}")
    end

    state
  end

  defp claim_task(state, task, proxy) do
    title = shorten(clean_text(get(task, "title", ""), "task"), "task", 22)

    case call("/api/v2/tasks/claim", %{"userId" => state.id, "taskId" => get(task, "id", "")}, state, proxy) do
      {:ok, data} ->
        if truthy(get(data, "success", false)) do
          green("Task #{title} verified #{amount(get(data, "reward", 0))} #{@token}")
        else
          yellow("Task #{title} was refused by the server")
        end

      {:error, reason} ->
        case String.upcase(stringify(reason)) do
          "MUST_JOIN_CHANNEL" -> yellow("Task #{title} must join the channel first")
          "TASK_ALREADY_COMPLETED" -> yellow("Task #{title} was already completed")
          _other -> yellow("Task #{title} was refused by the server")
        end
    end
  end

  defp process_referrals(state, user, proxy) do
    if number(get(user, "referralRewardAvailable", 0)) > 0 do
      case call("/api/referrals/claim-bonus", %{"userId" => state.id}, state, proxy) do
        {:ok, data} -> green("Invite bonus claimed #{amount(get(data, "claimedAtf", 0))} #{@token}")
        {:error, reason} -> yellow("Invite bonus was refused with #{short_reason(reason)}")
      end
    end

    if number(get(user, "teamWalletEarnings", 0)) > 0 do
      case call("/api/referrals/claim-team", %{"userId" => state.id}, state, proxy) do
        {:ok, data} -> green("Team commission claimed #{amount(get(data, "claimedAtf", 0))} #{@token}")
        {:error, reason} -> yellow("Team commission was refused with #{short_reason(reason)}")
      end
    end

    state
  end

  defp process_mining(state, snapshot, proxy) do
    mining = get(snapshot, "miningState", %{})
    user = get(snapshot, "user", %{})

    if truthy(get(mining, "isMining", false)) do
      green("Mining is already running with #{format_duration(whole(get(mining, "remainingSeconds", 0), 0))} left")
      state
    else
      state
      |> claim_mining(mining, proxy)
      |> start_mining(user, proxy)
    end
  end

  defp claim_mining(state, mining, proxy) do
    if number(get(mining, "accumulatedAtf", 0)) > 0 do
      case call("/api/user/claim-mining", %{"userId" => state.id}, state, proxy) do
        {:ok, data} -> green("Mining claim credited #{amount(get(data, "claimedAtf", 0))} #{@token}")
        {:error, reason} -> yellow("Mining claim was refused with #{short_reason(reason)}")
      end
    end

    state
  end

  defp start_mining(state, user, proxy) do
    wallet = get(user, "tonWalletAddress", nil)

    if is_binary(wallet) and wallet != "" do
      case call("/api/user/start-mining", %{"userId" => state.id}, state, proxy) do
        {:ok, data} ->
          mining = get(data, "miningState", %{})
          speed = number(get(mining, "currentSpeedTh", 0))
          left = whole(get(mining, "remainingSeconds", 0), 0)

          green("Mining started at #{amount(speed)} TH with #{format_duration(left)} left")

        {:error, reason} ->
          case String.upcase(stringify(reason)) do
            "WALLET_REQUIRED" -> red("Mining needs a TON wallet on this account")
            _other -> yellow("Mining start was refused with #{short_reason(reason)}")
          end
      end
    else
      red("Mining needs a TON wallet on this account")
    end

    state
  end

  defp fetch_user(state, proxy) do
    path =
      "/api/user/#{state.id}?username=#{URI.encode_www_form(state.username)}" <>
        "&firstName=#{URI.encode_www_form(state.first_name)}&referredBy="

    call_get(path, state, proxy)
  end

  defp init_data_of(line) do
    value =
      line
      |> String.trim()
      |> String.trim_leading("\"")
      |> String.trim_trailing("\"")

    value = extract_init_data(value)

    if value == "" do
      :error
    else
      try do
        case URI.decode_query(value) do
          %{"user" => raw} ->
            case YuurisanJSON.decode(raw) do
              {:ok, %{"id" => id} = profile} -> {:ok, value, to_string(id), profile}
              _other -> :error
            end

          _other ->
            :error
        end
      rescue
        _error -> :error
      end
    end
  end

  defp extract_init_data(value) do
    if String.contains?(value, "tgWebAppData=") do
      value
      |> String.split("tgWebAppData=")
      |> List.last()
      |> String.split("&tgWebApp")
      |> List.first()
      |> URI.decode_www_form()
    else
      value |> String.trim_leading("?") |> String.trim_leading("#")
    end
  end

  defp call(path, payload, state, proxy) do
    case request(:post, path, payload, state, proxy) do
      {:ok, body} -> unwrap(body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_get(path, state, proxy) do
    case request(:get, path, %{}, state, proxy) do
      {:ok, body} -> unwrap(body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp unwrap(body) do
    case body do
      %{"error" => error} -> {:error, error}
      %{} = data -> {:ok, data}
      _other -> {:ok, %{}}
    end
  end

  defp request(method, path, payload, state, proxy) do
    url = String.to_charlist(String.trim_trailing(@base_url, "/") <> path)
    {profile, auth} = proxy_setup(proxy)

    headers =
      [
        {~c"content-type", ~c"application/json"},
        {~c"accept", ~c"*/*"},
        {~c"accept-language", ~c"en-US,en;q=0.9"},
        {~c"origin", String.to_charlist(@base_url)},
        {~c"referer", String.to_charlist(@base_url <> "/")},
        {~c"x-telegram-init-data", String.to_charlist(state.init)},
        {~c"user-agent",
         ~c"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36"}
      ]

    body = payload |> YuurisanJSON.encode()

    options = [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    dispatch(method, url, headers, body, options, profile)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp dispatch(:get, url, headers, _body, options, profile) do
    handle(:httpc.request(:get, {url, headers}, options, [body_format: :binary], profile))
  end

  defp dispatch(:post, url, headers, body, options, profile) do
    handle(
      :httpc.request(
        :post,
        {url, headers, ~c"application/json", body},
        options,
        [body_format: :binary],
        profile
      )
    )
  end

  defp handle({:ok, {{_version, status, _reason}, _headers, response}})
       when status >= 200 and status < 300 do
    case YuurisanJSON.decode(response) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, "unreadable response"}
    end
  end

  defp handle({:ok, {{_version, status, _reason}, _headers, response}}) do
    case YuurisanJSON.decode(response) do
      {:ok, %{"error" => error}} -> {:error, error}
      {:ok, %{"message" => message}} -> {:error, message}
      {:ok, _value} -> {:error, "HTTP #{status}"}
      {:error, _reason} -> {:error, "HTTP #{status}"}
    end
  end

  defp handle({:error, reason}), do: {:error, reason}

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} -> :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)
      {:error, {:already_started, _pid}} -> :ok
      _other -> :ok
    end

    case user do
      "" -> {name, []}
      _ -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value =
      line
      |> String.trim()
      |> String.replace_prefix("http://", "")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _other -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _other -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _other -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _other -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _other -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] ->
        "#{a}*****#{d}"

      _other ->
        if String.length(host) > 4 do
          String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2)
        else
          "***"
        end
    end
  end

  defp proxy_for([], _index), do: nil
  defp proxy_for(proxies, index), do: Enum.at(proxies, rem(index, length(proxies)))

  defp load_lines(name) do
    case File.read(Path.join(__DIR__, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp load_settings do
    case File.read(Path.join(__DIR__, "config.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, %{"settings" => settings}} when is_map(settings) -> settings
          _other -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  end

  defp sleep_seconds(settings), do: whole(get(settings, "sleep_seconds", 3600), 3600)

  defp install_signal_handler do
    handler = fn ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.halt(0)
    end

    for signal <- [:sigterm, :sighup, :sigquit] do
      try do
        System.trap_signal(signal, handler)
      rescue
        _error -> :ok
      end
    end
  end

  defp clean_text(value, fallback) do
    text =
      value
      |> stringify()
      |> String.replace(
        ["[", "]", "|", "#", "!", "@", "$", "%", "^", "&", "*", "(", ")", "-"],
        " "
      )

    case String.split(text) |> Enum.join(" ") do
      "" -> fallback
      cleaned -> cleaned
    end
  end

  defp short_reason(reason), do: shorten(clean_text(reason, "reason"), "reason", 26)

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp stringify({:failed_connect, _reason}), do: "no network connection"
  defp stringify({:timeout, _reason}), do: "the request timed out"
  defp stringify({:failed_connect, _reason, _host}), do: "no network connection"
  defp stringify(value), do: inspect(value)

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_other, _key, default), do: default

  defp truthy(value), do: value == true

  defp whole(value, _fallback) when is_integer(value), do: value
  defp whole(value, _fallback) when is_float(value), do: trunc(value)
  defp whole(_value, fallback), do: fallback

  defp number(value) when is_integer(value), do: value
  defp number(value) when is_float(value), do: value
  defp number(_value), do: 0

  defp amount(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp amount(value), do: to_string(value)

  defp shorten(value, fallback, limit) do
    text = value |> to_string() |> String.trim()

    case String.slice(text, 0, limit) do
      "" -> fallback
      short -> String.trim(short)
    end
  end

  defp fit(text) do
    value = to_string(text)
    if String.length(value) <= 63, do: value, else: String.slice(value, 0, 63)
  end

  defp countdown(seconds, label) do
    left = max(trunc(seconds), 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width)
    end
  end

  defp tick(0, _label, width) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width) do
    width = frame(label, left, width)
    :timer.sleep(1000)
    tick(left - 1, label, width)
  end

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp green(message), do: IO.puts(@green <> @bold <> fit(message) <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> fit(message) <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> fit(message) <> @reset)
end

AFLMining.run()
