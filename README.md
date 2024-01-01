<a name="readme-top"></a>

# Zedex

*Version:* `0.0.1-prerelease`

> [!WARNING]
> This is VERY early days of this project. I would not recommend using this for
> anything serious at this time.

<!-- PROJECT SHIELDS -->

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT][license-shield]][license-url]

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About the Project

This library allows patching and replacing functions in existing modules with
your own, effectively turning them into zombies (or zeds) 🧟. This is useful if
you need to hook into some existing code that has no other way to be modified.

⚠ You probably don't want to use this library in live production code. Its original
intent is to help mock low-level Erlang operations.

### Built With

<!-- Tools the project is built with -->

[![Elixir][elixir-badge]][elixir-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

Add add Zedex to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:zedex, git: "git@github.com:chriskdon/zedex.git", branch: "main"}
  ]
end
```

> [!NOTE]
> Eventually this will be published to Hex once there is a minimal feature set.

Run `mix deps.get`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->
## Usage

```elixir
# replace :random.uniform/1 and :random with MyRandom.uniform/1
:ok = Zedex.replace([
  {{:random, :uniform, 1}, {MyRandom, :constant_uniform, 1}},
  {{:rand, :uniform, 1}, {MyRandom, :constant_uniform, 1}},
])

:ok = Zedex.replace_with({:random, :uniform, 1}, {MyRandom, :constant_uniform, 1})

# replace :erlang.uniform/1 with anonymous function
:ok = Zedex.replace_with({:random, :uniform, 1}, fn n ->
  1
end)

# Replace calls in GenServer.call/3 to :gen.call/4
# with ReplacementModule.capture_call/4
:ok = Zedex.replace_calls(
  {GenServer, :call, 3},
  {:gen, :call, 4},
  {ReplacementModule, :capture_call, 4}
)

# or use an anonymous function
:ok = Zedex.replace_calls(
  {GenServer, :call, 3},
  {:gen, :call, 4},
  fn server, label, msg, timeout  ->
    Logger.info("#{inspect(self())} sent #{inspect(msg)} to #{inspect(server)}")

    # Perform the real call
    :gen.call(server, label, msg, timeout)
  end
)

# reset all modules back to their original versions
:ok = Zedex.reset()
```

Run `mix docs --open` for the complete documentation.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->
## License

Distributed under the MIT license. See `LICENSE.txt` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- Generic Links -->
[contributors-shield]: https://img.shields.io/github/contributors/chriskdon/zedex.svg?style=for-the-badge
[contributors-url]: https://github.com/chriskdon/zedex/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/chriskdon/zedex.svg?style=for-the-badge
[forks-url]: https://github.com/chriskdon/zedex/network/members
[stars-shield]: https://img.shields.io/github/stars/chriskdon/zedex.svg?style=for-the-badge
[stars-url]: https://github.com/chriskdon/zedex/stargazers
[issues-shield]: https://img.shields.io/github/issues/chriskdon/zedex.svg?style=for-the-badge
[issues-url]: https://github.com/chriskdon/zedex/issues
[license-shield]: https://img.shields.io/github/license/chriskdon/zedex.svg?style=for-the-badge
[license-url]: https://github.com/chriskdon/zedex/blob/main/LICENSE.txt

<!-- Built With Links (see: https://shields.io/badges) -->
[elixir-badge]: https://img.shields.io/badge/Elixir-000000?style=for-the-badge&logoColor=white
[elixir-url]: https://elixir-lang.org/
