# Copyright (c) 2009 Paolo Capriotti <p.capriotti@gmail.com>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

require 'korundum4'

ParseException = Class.new(Exception)

module Enumerable
  def detect_index
    i = 0
    each do |item|
      return i if yield item
      i += 1
    end
    
    nil
  end
end

class Hash
  def with_symbol_keys
    result = { }
    each do |key, value|
      result[key.to_sym] = value
    end
  end
end

class Qt::Painter
  def paint
    yield self
  ensure
    self.end
  end
  
  def saving
    save
    yield self
  ensure
    restore
  end
end

class Qt::Image
  def to_pix
    Qt::Pixmap.from_image self
  end
  
  def self.painted(size, &blk)
    Qt::Image.new(size.x, size.y, Qt::Image::Format_ARGB32_Premultiplied).tap do |img|
      img.fill(0)
      Qt::Painter.new(img).paint(&blk)
    end
  end

  def self.from_renderer(size, renderer, id = nil)
    img = Qt::Image.painted(size) do |p| 
      if id
        renderer.render(p, id)
      else
        renderer.render(p)
      end
    end
    img
  end
end

module PrintablePoint
  def ==(other)
    self.x == other.x and self.y == other.y
  end
  
  def to_s
    "(#{self.x}, #{self.y})"
  end
end

module PrintableRect
  def to_s
    "[#{self.x}, #{self.y} - #{self.width}, #{self.height}]"
  end
end

class Qt::Point
  include PrintablePoint
  
  def to_f
    Qt::PointF.new(self.x, self.y)
  end
end

class Qt::PointF
  include PrintablePoint
  
  def to_i
    Qt::Point.new(self.x.to_i, self.y.to_i)
  end
end

class Qt::Size
  include PrintablePoint
  
  def x
    width
  end
  
  def y
    height
  end
end

class Qt::SizeF
  include PrintablePoint
  
  def x
    width
  end
  
  def y
    height
  end
end

class Qt::Rect
  include PrintableRect
  
  def to_f
    Qt::RectF.new(x, y, width, height)
  end
end

class Qt::RectF
  include PrintableRect
end

class Qt::Pixmap
  def self.from_svg(size, file, id = nil)
    from_renderer(size, Qt::SvgRenderer.new(file), id)
  end
  
  def self.from_renderer(size, renderer, id = nil)
    Qt::Image.from_renderer(size, renderer, id).to_pix
  end
end

class Qt::Base
  def self.signal_map(sigmap)
    @signal_map = sigmap
    signals *sigmap.map{|k, v| v || k }
  end

  def self.get_signal(sig)
    (@signal_map || {})[sig] || sig
  end

  def on(sig, &blk)
    connect(SIGNAL(self.class.get_signal(sig)), &blk)
  end  

  def in(interval, &blk)
    Qt::Timer.in(interval, self, &blk)
  end

  def run_later(&blk)
    self.in(0, &blk)
  end
end

class Qt::Timer
  def self.every(interval, &blk)
    time = Qt::Time.new
    time.restart
    
    timer = new
    timer.connect(SIGNAL('timeout()')) { blk[time.elapsed] }
    timer.start(interval)
    # return the timer, so that the caller
    # has a chance to keep it referenced, so
    # that it is not garbage collected
    timer
  end

  def self.in(interval, target = nil, &blk)
    single_shot(interval,
                Qt::BlockInvocation.new(target, blk, 'invoke()'),
                SLOT('invoke()'))
  end
end

module ModelUtils
  def removing_rows(parent, first, last)
    if first > last
      yield
    else
      begin
        begin_remove_rows(parent || Qt::ModelIndex.new, first, last)
        yield
      ensure
        end_remove_rows
      end
    end
  end
  
  def inserting_rows(parent, first, last)
    if first > last
      yield
    else
      begin
        begin_insert_rows(parent || Qt::ModelIndex.new, first, last)
        yield
      ensure
        end_insert_rows
      end
    end
  end
end

class KDE::Application
  def self.init(data)
    about = KDE::AboutData.new(
      data[:id],
      data[:id],
      data[:name],
      data[:version],
      data[:description],
      KDE::AboutData::License_GPL,
      data[:copyright])
    (data[:authors] || []).each do |name, email|
      about.addAuthor(name, KDE::LocalizedString.new, email)
    end
    (data[:contributors] || []).each do |name, contribution|
      about.addCredit(name, contribution)
    end
    if data[:bug_tracker]
      about.bug_address = Qt::ByteArray.new(data[:bug_tracker])
    end
    
    KDE::CmdLineArgs.init(ARGV, about)
    if data[:options]
      KDE::CmdLineOptions.new.tap do |opts|
        data[:options].each do |opt, desc|
          opts.add(opt, desc)
        end
        KDE::CmdLineArgs.add_cmd_line_options opts
      end
    end

    KDE::Application.new
  end
end

module ActionHandler
  def std_action(action, opts = {}, &blk)
    target, slot = get_slot(opts[:slot], &blk)
    KDE::StandardAction.method_missing(action, target, slot, action_collection)
  end
  
  def get_slot(s = nil, &blk)
    target, slot = if block_given?
      [Qt::SignalBlockInvocation.new(action_parent, blk, 'invoke()'), SLOT('invoke()')]
    else
      [action_parent, SLOT(s)]
    end
  end
  
  def regular_action(name, opts, &blk)
    icon = if opts[:icon]
      case opts[:icon]
      when Qt::Icon
        opts[:icon]
      else
        KDE::Icon.new(opts[:icon].to_s)
      end
    else
      KDE::Icon.new
    end
    
    KDE::Action.new(icon, opts[:text], action_parent).tap do |a|
      action_collection.add_action(name.to_s, a)  
      a.connect(SIGNAL('triggered(bool)'), &blk)
    end
  end
  
  def action_parent
    self
  end
end

class KDE::Config
  def each_group
    group_list.each do |g|
      yield group(g)
    end
  end
end
