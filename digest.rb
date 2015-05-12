#!/usr/bin/env ruby

require 'optparse'
require 'date'
require 'time'
require 'mediawiki_api'
require 'mail'

options = {}

OptionParser.new do |opts|
  opts.on('-u username', 'MediaWiki Username') { |u| options[:username] = u }
  opts.on('-p password', 'MediaWiki Password') { |p| options[:password] = p }
  opts.on('-b baseurl',  'MediaWiki Base URL (no trailing slash)') { |b| options[:baseurl] = b }
  opts.on('-t tag',  'Email Subject Prefix Tag') { |t| options[:tag] = t }
  opts.on('-f from', 'Email Sender') { |f| options[:from] = f }
  opts.on('-r to',   'Email Recipient') { |r| options[:recipient] = r }
end.parse!

yesterday = (Date.today - 1).to_time

title = "Daily Digest - #{yesterday.to_date}"
subject = "[#{options[:tag]}] #{title}"

client = MediawikiApi::Client.new("#{options[:baseurl]}/api.php")
client.log_in(options[:username], options[:password])

response = client.list(:recentchanges,
  rcnamespace: 0,
  rcprop: 'user|title',
  rclimit: 150,
  rcend: yesterday.utc.iso8601
)

if response.success?
  edits = response.data
    .group_by { |edit| [edit['title'], edit['user']] }
    .map { |k, v| [*k, v.count] }
    .map { |edit| ['title', 'user', 'edits'].zip(edit) }
    .map(&:to_h)

  if edits.length > 0
    mail = Mail.new do
      to options[:recipient]
      from options[:from]
      subject subject

      text_part do
        formatted = edits.inject('') { |r, edit| r += " * #{edit['user']} made #{edit['edits']} edit(s) to #{edit['title']} [#{options[:baseurl]}/#{edit['title'].gsub(' ', '_')}]\n" }
        body "#{title}:\n#{formatted}"
      end

      html_part do
        content_type 'text/html; charset=UTF-8'
        formatted = edits.inject('') { |r, edit| r += "<li>#{edit['user']} made #{edit['edits']} edit(s) to <a href=\"#{options[:baseurl]}/#{edit['title'].gsub(' ', '_')}\">#{edit['title']}</a></li>" }
        body "<p><strong>#{title}:</strong></p><ul>#{formatted}</ul>"
      end
    end

    mail.delivery_method :sendmail
    mail.deliver!
  end
end
