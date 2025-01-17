-- SQL to create the initial tables for the MediaWiki database.
-- This is read and executed by the install script; you should
-- not have to run it by itself unless doing a manual install.

-- This is a shared schema file used for both MySQL and SQLite installs.
--
-- For more documentation on the database schema, see
-- https://www.mediawiki.org/wiki/Manual:Database_layout
--
-- General notes:
--
-- If possible, create tables as InnoDB to benefit from the
-- superior resiliency against crashes and ability to read
-- during writes (and write during reads!)
--
-- Only the 'searchindex' table requires MyISAM due to the
-- requirement for fulltext index support, which is missing
-- from InnoDB.
--
--
-- The MySQL table backend for MediaWiki currently uses
-- 14-character BINARY or VARBINARY fields to store timestamps.
-- The format is YYYYMMDDHHMMSS, which is derived from the
-- text format of MySQL's TIMESTAMP fields.
--
-- Historically TIMESTAMP fields were used, but abandoned
-- in early 2002 after a lot of trouble with the fields
-- auto-updating.
--
-- The Postgres backend uses TIMESTAMPTZ fields for timestamps,
-- and we will migrate the MySQL definitions at some point as
-- well.
--
--
-- The /*_*/ comments in this and other files are
-- replaced with the defined table prefix by the installer
-- and updater scripts. If you are installing or running
-- updates manually, you will need to manually insert the
-- table prefix if any when running these scripts.
--


--
-- The user table contains basic account information,
-- authentication keys, etc.
--
-- Some multi-wiki sites may share a single central user table
-- between separate wikis using the $wgSharedDB setting.
--
-- Note that when an external authentication plugin is used,
-- user table entries still need to be created to store
-- preferences and to key tracking information in the other
-- tables.
--
CREATE TABLE /*_*/user (
  user_id int unsigned NOT NULL PRIMARY KEY AUTO_INCREMENT,

  -- Usernames must be unique, must not be in the form of
  -- an IP address. _Shouldn't_ allow slashes or case
  -- conflicts. Spaces are allowed, and are _not_ converted
  -- to underscores like titles. See the User::newFromName() for
  -- the specific tests that usernames have to pass.
  user_name varchar(255) binary NOT NULL default '',

  -- Optional 'real name' to be displayed in credit listings
  user_real_name varchar(255) binary NOT NULL default '',

  -- Password hashes, see User::crypt() and User::comparePasswords()
  -- in User.php for the algorithm
  user_password tinyblob NOT NULL,

  -- When using 'mail me a new password', a random
  -- password is generated and the hash stored here.
  -- The previous password is left in place until
  -- someone actually logs in with the new password,
  -- at which point the hash is moved to user_password
  -- and the old password is invalidated.
  user_newpassword tinyblob NOT NULL,

  -- Timestamp of the last time when a new password was
  -- sent, for throttling and expiring purposes
  -- Emailed passwords will expire $wgNewPasswordExpiry
  -- (a week) after being set. If user_newpass_time is NULL
  -- (eg. created by mail) it doesn't expire.
  user_newpass_time binary(14),

  -- Note: email should be restricted, not public info.
  -- Same with passwords.
  user_email tinytext NOT NULL,

  -- If the browser sends an If-Modified-Since header, a 304 response is
  -- suppressed if the value in this field for the current user is later than
  -- the value in the IMS header. That is, this field is an invalidation timestamp
  -- for the browser cache of logged-in users. Among other things, it is used
  -- to prevent pages generated for a previously logged in user from being
  -- displayed after a session expiry followed by a fresh login.
  user_touched binary(14) NOT NULL default '',

  -- A pseudorandomly generated value that is stored in
  -- a cookie when the "remember password" feature is
  -- used (previously, a hash of the password was used, but
  -- this was vulnerable to cookie-stealing attacks)
  user_token binary(32) NOT NULL default '',

  -- Initially NULL; when a user's e-mail address has been
  -- validated by returning with a mailed token, this is
  -- set to the current timestamp.
  user_email_authenticated binary(14),

  -- Randomly generated token created when the e-mail address
  -- is set and a confirmation test mail sent.
  user_email_token binary(32),

  -- Expiration date for the user_email_token
  user_email_token_expires binary(14),

  -- Timestamp of account registration.
  -- Accounts predating this schema addition may contain NULL.
  user_registration binary(14),

  -- Count of edits and edit-like actions.
  --
  -- *NOT* intended to be an accurate copy of COUNT(*) WHERE rev_actor refers to a user's actor_id
  -- May contain NULL for old accounts if batch-update scripts haven't been
  -- run, as well as listing deleted edits and other myriad ways it could be
  -- out of sync.
  --
  -- Meant primarily for heuristic checks to give an impression of whether
  -- the account has been used much.
  --
  user_editcount int,

  -- Expiration date for user password.
  user_password_expires varbinary(14) DEFAULT NULL

) /*$wgDBTableOptions*/;

CREATE UNIQUE INDEX /*i*/user_name ON /*_*/user (user_name);
CREATE INDEX /*i*/user_email_token ON /*_*/user (user_email_token);
CREATE INDEX /*i*/user_email ON /*_*/user (user_email(50));

--
-- Core of the wiki: each page has an entry here which identifies
-- it by title and contains some essential metadata.
--
CREATE TABLE /*_*/page (
  -- Unique identifier number. The page_id will be preserved across
  -- edits and rename operations, but not deletions and recreations.
  page_id int unsigned NOT NULL PRIMARY KEY AUTO_INCREMENT,

  -- A page name is broken into a namespace and a title.
  -- The namespace keys are UI-language-independent constants,
  -- defined in includes/Defines.php
  page_namespace int NOT NULL,

  -- The rest of the title, as text.
  -- Spaces are transformed into underscores in title storage.
  page_title varchar(255) binary NOT NULL,

  -- Comma-separated set of permission keys indicating who
  -- can move or edit the page.
  page_restrictions tinyblob NULL,

  -- 1 indicates the article is a redirect.
  page_is_redirect tinyint unsigned NOT NULL default 0,

  -- 1 indicates this is a new entry, with only one edit.
  -- Not all pages with one edit are new pages.
  page_is_new tinyint unsigned NOT NULL default 0,

  -- Random value between 0 and 1, used for Special:Randompage
  page_random real unsigned NOT NULL,

  -- This timestamp is updated whenever the page changes in
  -- a way requiring it to be re-rendered, invalidating caches.
  -- Aside from editing this includes permission changes,
  -- creation or deletion of linked pages, and alteration
  -- of contained templates.
  page_touched binary(14) NOT NULL default '',

  -- This timestamp is updated whenever a page is re-parsed and
  -- it has all the link tracking tables updated for it. This is
  -- useful for de-duplicating expensive backlink update jobs.
  page_links_updated varbinary(14) NULL default NULL,

  -- Handy key to revision.rev_id of the current revision.
  -- This may be 0 during page creation, but that shouldn't
  -- happen outside of a transaction... hopefully.
  page_latest int unsigned NOT NULL,

  -- Uncompressed length in bytes of the page's current source text.
  page_len int unsigned NOT NULL,

  -- content model, see CONTENT_MODEL_XXX constants
  page_content_model varbinary(32) DEFAULT NULL,

  -- Page content language
  page_lang varbinary(35) DEFAULT NULL
) /*$wgDBTableOptions*/;

-- The title index. Care must be taken to always specify a namespace when
-- by title, so that the index is used. Even listing all known namespaces
-- with IN() is better than omitting page_namespace from the WHERE clause.
CREATE UNIQUE INDEX /*i*/name_title ON /*_*/page (page_namespace,page_title);

-- The index for Special:Random
CREATE INDEX /*i*/page_random ON /*_*/page (page_random);

-- Questionable utility, used by ProofreadPage, possibly DynamicPageList.
-- ApiQueryAllPages unconditionally filters on namespace and so hopefully does
-- not use it.
CREATE INDEX /*i*/page_len ON /*_*/page (page_len);

-- The index for Special:Shortpages and Special:Longpages. Also SiteStats::articles()
-- in 'comma' counting mode, MessageCache::loadFromDB().
CREATE INDEX /*i*/page_redirect_namespace_len ON /*_*/page (page_is_redirect, page_namespace, page_len);

--
-- Every edit of a page creates also a revision row.
-- This stores metadata about the revision, and a reference
-- to the text storage backend.
--
CREATE TABLE /*_*/revision (
  -- Unique ID to identify each revision
  rev_id int unsigned NOT NULL PRIMARY KEY AUTO_INCREMENT,

  -- Key to page_id. This should _never_ be invalid.
  rev_page int unsigned NOT NULL,

  -- Key to comment.comment_id. Comment summarizing the change.
  rev_comment_id bigint unsigned NOT NULL default 0,

  -- Key to actor.actor_id of the user or IP who made this edit.
  rev_actor bigint unsigned NOT NULL default 0,

  -- Timestamp of when revision was created
  rev_timestamp binary(14) NOT NULL default '',

  -- Records whether the user marked the 'minor edit' checkbox.
  -- Many automated edits are marked as minor.
  rev_minor_edit tinyint unsigned NOT NULL default 0,

  -- Restrictions on who can access this revision
  rev_deleted tinyint unsigned NOT NULL default 0,

  -- Length of this revision in bytes
  rev_len int unsigned,

  -- Key to revision.rev_id
  -- This field is used to add support for a tree structure (The Adjacency List Model)
  rev_parent_id int unsigned default NULL,

  -- SHA-1 text content hash in base-36
  rev_sha1 varbinary(32) NOT NULL default ''
) /*$wgDBTableOptions*/ MAX_ROWS=10000000 AVG_ROW_LENGTH=1024;
-- In case tables are created as MyISAM, use row hints for MySQL <5.0 to avoid 4GB limit

-- The index is proposed for removal, do not use it in new code: T163532.
-- Used for ordering revisions within a page by rev_id, which is usually
-- incorrect, since rev_timestamp is normally the correct order. It can also
-- be used by dumpBackup.php, if a page and rev_id range is specified.
CREATE INDEX /*i*/rev_page_id ON /*_*/revision (rev_page, rev_id);

-- Used by ApiQueryAllRevisions
CREATE INDEX /*i*/rev_timestamp ON /*_*/revision (rev_timestamp);

-- History index
CREATE INDEX /*i*/page_timestamp ON /*_*/revision (rev_page,rev_timestamp);

-- User contributions index
CREATE INDEX /*i*/rev_actor_timestamp ON /*_*/revision (rev_actor,rev_timestamp,rev_id);

-- Credits index. This is scanned in order to compile credits lists for pages,
-- in ApiQueryContributors. Also for ApiQueryRevisions if rvuser is specified.
CREATE INDEX /*i*/rev_page_actor_timestamp ON /*_*/revision (rev_page,rev_actor,rev_timestamp);

--
-- Archive area for deleted pages and their revisions.
-- These may be viewed (and restored) by admins through the Special:Undelete interface.
--
CREATE TABLE /*_*/archive (
  -- Primary key
  ar_id int unsigned NOT NULL PRIMARY KEY AUTO_INCREMENT,

  -- Copied from page_namespace
  ar_namespace int NOT NULL default 0,
  -- Copied from page_title
  ar_title varchar(255) binary NOT NULL default '',

  -- Basic revision stuff...
  ar_comment_id bigint unsigned NOT NULL,
  ar_actor bigint unsigned NOT NULL,
  ar_timestamp binary(14) NOT NULL default '',
  ar_minor_edit tinyint NOT NULL default 0,

  -- Copied from rev_id.
  --
  -- @since 1.5 Entries from 1.4 will be NULL here. When restoring
  -- archive rows from before 1.5, a new rev_id is created.
  ar_rev_id int unsigned NOT NULL,

  -- Copied from rev_deleted. Although this may be raised during deletion.
  -- Users with the "suppressrevision" right may "archive" and "suppress"
  -- content in a single action.
  -- @since 1.10
  ar_deleted tinyint unsigned NOT NULL default 0,

  -- Copied from rev_len, length of this revision in bytes.
  -- @since 1.10
  ar_len int unsigned,

  -- Copied from page_id. Restoration will attempt to use this as page ID if
  -- no current page with the same name exists. Otherwise, the revisions will
  -- be restored under the current page. Can be used for manual undeletion by
  -- developers if multiple pages by the same name were archived.
  --
  -- @since 1.11 Older entries will have NULL.
  ar_page_id int unsigned,

  -- Copied from rev_parent_id.
  -- @since 1.13
  ar_parent_id int unsigned default NULL,

  -- Copied from rev_sha1, SHA-1 text content hash in base-36
  -- @since 1.19
  ar_sha1 varbinary(32) NOT NULL default ''
) /*$wgDBTableOptions*/;

-- Index for Special:Undelete to page through deleted revisions
CREATE INDEX /*i*/ar_name_title_timestamp ON /*_*/archive (ar_namespace,ar_title,ar_timestamp);

-- Index for Special:DeletedContributions
CREATE INDEX /*i*/ar_actor_timestamp ON /*_*/archive (ar_actor,ar_timestamp);

-- Index for linking archive rows with tables that normally link with revision
-- rows, such as change_tag.
CREATE UNIQUE INDEX /*i*/ar_revid_uniq ON /*_*/archive (ar_rev_id);


--
-- Primarily a summary table for Special:Recentchanges,
-- this table contains some additional info on edits from
-- the last few days, see Article::editUpdates()
--
CREATE TABLE /*_*/recentchanges (
  rc_id int NOT NULL PRIMARY KEY AUTO_INCREMENT,
  rc_timestamp varbinary(14) NOT NULL default '',

  -- As in revision
  rc_actor bigint unsigned NOT NULL,

  -- When pages are renamed, their RC entries do _not_ change.
  rc_namespace int NOT NULL default 0,
  rc_title varchar(255) binary NOT NULL default '',

  -- as in revision...
  rc_comment_id bigint unsigned NOT NULL,
  rc_minor tinyint unsigned NOT NULL default 0,

  -- Edits by user accounts with the 'bot' rights key are
  -- marked with a 1 here, and will be hidden from the
  -- default view.
  rc_bot tinyint unsigned NOT NULL default 0,

  -- Set if this change corresponds to a page creation
  rc_new tinyint unsigned NOT NULL default 0,

  -- Key to page_id (was cur_id prior to 1.5).
  -- This will keep links working after moves while
  -- retaining the at-the-time name in the changes list.
  rc_cur_id int unsigned NOT NULL default 0,

  -- rev_id of the given revision
  rc_this_oldid int unsigned NOT NULL default 0,

  -- rev_id of the prior revision, for generating diff links.
  rc_last_oldid int unsigned NOT NULL default 0,

  -- The type of change entry (RC_EDIT,RC_NEW,RC_LOG,RC_EXTERNAL)
  rc_type tinyint unsigned NOT NULL default 0,

  -- The source of the change entry (replaces rc_type)
  -- default of '' is temporary, needed for initial migration
  rc_source varchar(16) binary not null default '',

  -- If the Recent Changes Patrol option is enabled,
  -- users may mark edits as having been reviewed to
  -- remove a warning flag on the RC list.
  -- A value of 1 indicates the page has been reviewed.
  rc_patrolled tinyint unsigned NOT NULL default 0,

  -- Recorded IP address the edit was made from, if the
  -- $wgPutIPinRC option is enabled.
  rc_ip varbinary(40) NOT NULL default '',

  -- Text length in characters before
  -- and after the edit
  rc_old_len int,
  rc_new_len int,

  -- Visibility of recent changes items, bitfield
  rc_deleted tinyint unsigned NOT NULL default 0,

  -- Value corresponding to log_id, specific log entries
  rc_logid int unsigned NOT NULL default 0,
  -- Store log type info here, or null
  rc_log_type varbinary(255) NULL default NULL,
  -- Store log action or null
  rc_log_action varbinary(255) NULL default NULL,
  -- Log params
  rc_params blob NULL
) /*$wgDBTableOptions*/;

-- Special:Recentchanges
CREATE INDEX /*i*/rc_timestamp ON /*_*/recentchanges (rc_timestamp);

-- Special:Watchlist
CREATE INDEX /*i*/rc_namespace_title_timestamp ON /*_*/recentchanges (rc_namespace, rc_title, rc_timestamp);

-- Special:Recentchangeslinked when finding changes in pages linked from a page
CREATE INDEX /*i*/rc_cur_id ON /*_*/recentchanges (rc_cur_id);

-- Special:Newpages
CREATE INDEX /*i*/new_name_timestamp ON /*_*/recentchanges (rc_new,rc_namespace,rc_timestamp);

-- Blank unless $wgPutIPinRC=true (false at WMF), possibly used by extensions,
-- but mostly replaced by CheckUser.
CREATE INDEX /*i*/rc_ip ON /*_*/recentchanges (rc_ip);

-- Probably intended for Special:NewPages namespace filter
CREATE INDEX /*i*/rc_ns_actor ON /*_*/recentchanges (rc_namespace, rc_actor);

-- SiteStats active user count, Special:ActiveUsers, Special:NewPages user filter
CREATE INDEX /*i*/rc_actor ON /*_*/recentchanges (rc_actor, rc_timestamp);

-- ApiQueryRecentChanges (T140108)
CREATE INDEX /*i*/rc_name_type_patrolled_timestamp ON /*_*/recentchanges (rc_namespace, rc_type, rc_patrolled, rc_timestamp);

-- Article.php and friends (T139012)
CREATE INDEX /*i*/rc_this_oldid ON /*_*/recentchanges (rc_this_oldid);


--
-- When using the default MySQL search backend, page titles
-- and text are munged to strip markup, do Unicode case folding,
-- and prepare the result for MySQL's fulltext index.
--
-- This table must be MyISAM; InnoDB does not support the needed
-- fulltext index.
--
CREATE TABLE /*_*/searchindex (
  -- Key to page_id
  si_page int unsigned NOT NULL,

  -- Munged version of title
  si_title varchar(255) NOT NULL default '',

  -- Munged version of body text
  si_text mediumtext NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

CREATE UNIQUE INDEX /*i*/si_page ON /*_*/searchindex (si_page);
CREATE FULLTEXT INDEX /*i*/si_title ON /*_*/searchindex (si_title);
CREATE FULLTEXT INDEX /*i*/si_text ON /*_*/searchindex (si_text);

-- vim: sw=2 sts=2 et
