<?php

/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 * http://www.gnu.org/copyleft/gpl.html
 *
 * @file
 */

use MediaWiki\MediaWikiServices;

/**
 * @ingroup API
 * @since 1.25
 */
class ApiTag extends ApiBase {

	use ApiBlockInfoTrait;

	/** @var \MediaWiki\Revision\RevisionStore */
	private $revisionStore;

	public function execute() {
		$this->revisionStore = MediaWikiServices::getInstance()->getRevisionStore();

		$params = $this->extractRequestParams();
		$user = $this->getUser();

		// make sure the user is allowed
		$this->checkUserRightsAny( 'changetags' );

		// Fail early if the user is sitewide blocked.
		$block = $user->getBlock();
		if ( $block && $block->isSitewide() ) {
			$this->dieBlocked( $block );
		}

		// Check if user can add tags
		if ( $params['tags'] ) {
			$ableToTag = ChangeTags::canAddTagsAccompanyingChange( $params['tags'], $user );
			if ( !$ableToTag->isOK() ) {
				$this->dieStatus( $ableToTag );
			}
		}

		// validate and process each revid, rcid and logid
		$this->requireAtLeastOneParameter( $params, 'revid', 'rcid', 'logid' );
		$ret = [];
		if ( $params['revid'] ) {
			foreach ( $params['revid'] as $id ) {
				$ret[] = $this->processIndividual( 'revid', $params, $id );
			}
		}
		if ( $params['rcid'] ) {
			foreach ( $params['rcid'] as $id ) {
				$ret[] = $this->processIndividual( 'rcid', $params, $id );
			}
		}
		if ( $params['logid'] ) {
			foreach ( $params['logid'] as $id ) {
				$ret[] = $this->processIndividual( 'logid', $params, $id );
			}
		}

		ApiResult::setIndexedTagName( $ret, 'result' );
		$this->getResult()->addValue( null, $this->getModuleName(), $ret );
	}

	protected static function validateLogId( $logid ) {
		$dbr = wfGetDB( DB_REPLICA );
		$result = $dbr->selectField( 'logging', 'log_id', [ 'log_id' => $logid ],
			__METHOD__ );
		return (bool)$result;
	}

	protected function processIndividual( $type, $params, $id ) {
		$user = $this->getUser();
		$idResult = [ $type => $id ];

		// validate the ID
		$valid = false;
		switch ( $type ) {
			case 'rcid':
				$valid = RecentChange::newFromId( $id );
				// TODO: replace use of PermissionManager
				if ( $valid && $this->getPermissionManager()->isBlockedFrom( $user, $valid->getTitle() ) ) {
					$idResult['status'] = 'error';
					// @phan-suppress-next-line PhanTypeMismatchArgument
					$idResult += $this->getErrorFormatter()->formatMessage( ApiMessage::create(
						'apierror-blocked',
						'blocked',
						[ 'blockinfo' => $this->getBlockDetails( $user->getBlock() ) ]
					) );
					return $idResult;
				}
				break;
			case 'revid':
				$valid = $this->revisionStore->getRevisionById( $id );
				// TODO: replace use of PermissionManager
				if (
					$valid &&
					$this->getPermissionManager()->isBlockedFrom( $user, $valid->getPageAsLinkTarget() )
				) {
					$idResult['status'] = 'error';
					// @phan-suppress-next-line PhanTypeMismatchArgument
					$idResult += $this->getErrorFormatter()->formatMessage( ApiMessage::create(
							'apierror-blocked',
							'blocked',
							[ 'blockinfo' => $this->getBlockDetails( $user->getBlock() ) ]
					) );
					return $idResult;
				}
				break;
			case 'logid':
				$valid = self::validateLogId( $id );
				break;
		}

		if ( !$valid ) {
			$idResult['status'] = 'error';
			// Messages: apierror-nosuchrcid apierror-nosuchrevid apierror-nosuchlogid
			$idResult += $this->getErrorFormatter()->formatMessage( [ "apierror-nosuch$type", $id ] );
			return $idResult;
		}

		$status = ChangeTags::updateTagsWithChecks( $params['add'],
			$params['remove'],
			( $type === 'rcid' ? $id : null ),
			( $type === 'revid' ? $id : null ),
			( $type === 'logid' ? $id : null ),
			null,
			$params['reason'],
			$this->getUser() );

		if ( !$status->isOK() ) {
			if ( $status->hasMessage( 'actionthrottledtext' ) ) {
				$idResult['status'] = 'skipped';
			} else {
				$idResult['status'] = 'failure';
				$idResult['errors'] = $this->getErrorFormatter()->arrayFromStatus( $status, 'error' );
			}
		} else {
			$idResult['status'] = 'success';
			if ( $status->value->logId === null ) {
				$idResult['noop'] = true;
			} else {
				$idResult['actionlogid'] = $status->value->logId;
				$idResult['added'] = $status->value->addedTags;
				ApiResult::setIndexedTagName( $idResult['added'], 't' );
				$idResult['removed'] = $status->value->removedTags;
				ApiResult::setIndexedTagName( $idResult['removed'], 't' );

				if ( $params['tags'] ) {
					ChangeTags::addTags( $params['tags'], null, null, $status->value->logId );
				}
			}
		}
		return $idResult;
	}

	public function mustBePosted() {
		return true;
	}

	public function isWriteMode() {
		return true;
	}

	public function getAllowedParams() {
		return [
			'rcid' => [
				ApiBase::PARAM_TYPE => 'integer',
				ApiBase::PARAM_ISMULTI => true,
			],
			'revid' => [
				ApiBase::PARAM_TYPE => 'integer',
				ApiBase::PARAM_ISMULTI => true,
			],
			'logid' => [
				ApiBase::PARAM_TYPE => 'integer',
				ApiBase::PARAM_ISMULTI => true,
			],
			'add' => [
				ApiBase::PARAM_TYPE => 'tags',
				ApiBase::PARAM_ISMULTI => true,
			],
			'remove' => [
				ApiBase::PARAM_TYPE => 'string',
				ApiBase::PARAM_ISMULTI => true,
			],
			'reason' => [
				ApiBase::PARAM_DFLT => '',
			],
			'tags' => [
				ApiBase::PARAM_TYPE => 'tags',
				ApiBase::PARAM_ISMULTI => true,
			],
		];
	}

	public function needsToken() {
		return 'csrf';
	}

	protected function getExamplesMessages() {
		return [
			'action=tag&revid=123&add=vandalism&token=123ABC'
				=> 'apihelp-tag-example-rev',
			'action=tag&logid=123&remove=spam&reason=Wrongly+applied&token=123ABC'
				=> 'apihelp-tag-example-log',
		];
	}

	public function getHelpUrls() {
		return 'https://www.mediawiki.org/wiki/Special:MyLanguage/API:Tag';
	}
}
