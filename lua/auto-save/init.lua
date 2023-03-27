local M = {}

local cnf = require("auto-save.config")
local callback = require("auto-save.utils.data").do_callback
local colors = require("auto-save.utils.colors")
local echo = require("auto-save.utils.echo")
local autosave_running
local api = vim.api
local g = vim.g
local fn = vim.fn
local cmd = vim.cmd
local o = vim.o
local AUTO_SAVE_COLOR = "MsgArea"
local BLACK = "#000000"
local WHITE = "#ffffff"

api.nvim_create_augroup("AutoSave", {
  clear = true,
})

local timers_by_buffer = {}

-- comm
local function cancel_timer(buf)
  local timer = timers_by_buffer[buf]
  print('cancel timer')
  print("buffer", buf)
  print("timer", vim.inspect(timer))
  if timer ~= nil then
    fn.timer_stop(timer)
    timers_by_buffer[buf] = nil
  end
end

local function debounce(lfn, duration)
  local function inner_debounce(buf)
    cancel_timer(buf)
      local timer = vim.defer_fn(function()
        lfn(buf)
        timers_by_buffer[buf] = nil
      end, duration)
      print('defer timer')
      print("buffer", buf)
      print("timer", vim.inspect(timer))
      timers_by_buffer[buf] = timer
    end
    return inner_debounce
end

local function echo_execution_message()
  local msg = type(cnf.opts.execution_message.message) == "function" and cnf.opts.execution_message.message()
    or cnf.opts.execution_message.message
  api.nvim_echo({ { msg, AUTO_SAVE_COLOR } }, true, {})
  if cnf.opts.execution_message.cleaning_interval > 0 then
    fn.timer_start(cnf.opts.execution_message.cleaning_interval, function()
      cmd([[echon '']])
    end)
  end
end

local function save(buf)
  print('saving')
  print("buffer", buf)

  callback("before_asserting_save")

  if cnf.opts.condition(buf) == false then
    return
  end

  if not api.nvim_buf_get_option(buf, "modified") then
    return
  end

  callback("before_saving")

  -- why is this needed? auto_save_abort is never set to true?
  -- TODO: remove?
  if g.auto_save_abort == true then
    return
  end

  if cnf.opts.write_all_buffers then
    cmd("silent! wall")
  else
    api.nvim_buf_call(buf, function()
      cmd("silent! write")
    end)
  end

  callback("after_saving")

  if cnf.opts.execution_message.enabled == true then
    echo_execution_message()
  end
end

function M.immediate_save(buf)
    buf = buf or api.nvim_get_current_buf()
    cancel_timer(buf)
    save(buf)
end


local save_func = nil
local function defer_save(buf)
  -- why is this needed? auto_save_abort is never set to true anyways?
  -- TODO: remove?
  g.auto_save_abort = false

  -- is it really needed to cache this function
  -- TODO: remove?
  if save_func == nil then
    save_func = (cnf.opts.debounce_delay > 0 and debounce(save, cnf.opts.debounce_delay) or save)
  end
  save_func(buf)
end

function M.on()
  api.nvim_create_autocmd(cnf.opts.trigger_events.immediate_save, {
    callback = function (opts)
        M.immediate_save(opts.buf)
    end,
    group = "AutoSave",
    desc = "Immediately save a buffer"
  })
  api.nvim_create_autocmd(cnf.opts.trigger_events.defer_save, {
    callback = function(opts)
      defer_save(opts.buf)
    end,
    group = "AutoSave",
    desc = "Save a buffer after the `debounce_delay`"
  })
  api.nvim_create_autocmd(cnf.opts.trigger_events.cancel_defered_save, {
    callback = function (opts)
      cancel_timer(opts.buf)
    end,
    group = "AutoSave",
    desc = "Cancel a pending save timer for a buffer"
  })

  api.nvim_create_autocmd({ "VimEnter", "ColorScheme", "UIEnter" }, {
    callback = function()
      vim.schedule(function()
        if cnf.opts.execution_message.dim > 0 then
          MSG_AREA = colors.get_hl("MsgArea")
          if MSG_AREA.foreground ~= nil then
            MSG_AREA.background = (MSG_AREA.background or colors.get_hl("Normal")["background"])
            local foreground = (
              o.background == "dark"
                and colors.darken(
                  (MSG_AREA.background or BLACK),
                  cnf.opts.execution_message.dim,
                  MSG_AREA.foreground or BLACK
                )
              or colors.lighten(
                (MSG_AREA.background or WHITE),
                cnf.opts.execution_message.dim,
                MSG_AREA.foreground or WHITE
              )
            )

            colors.highlight("AutoSaveText", { fg = foreground })
            AUTO_SAVE_COLOR = "AutoSaveText"
          end
        end
      end)
    end,
    group = "AutoSave",
  })

  callback("enabling")
  autosave_running = true
end

function M.off()
  api.nvim_create_augroup("AutoSave", {
    clear = true,
  })

  callback("disabling")
  autosave_running = false
end

function M.toggle()
  if autosave_running then
    M.off()
    echo("off")
  else
    M.on()
    echo("on")
  end
end

function M.setup(custom_opts)
  cnf:set_options(custom_opts)
end

return M
