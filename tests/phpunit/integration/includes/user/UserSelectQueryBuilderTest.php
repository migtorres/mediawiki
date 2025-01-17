<?php

namespace MediaWiki\Tests\User;

use MediaWiki\User\UserIdentityValue;
use MediaWiki\User\UserSelectQueryBuilder;
use Wikimedia\Rdbms\SelectQueryBuilder;

/**
 * @group Database
 * @covers \MediaWiki\User\UserSelectQueryBuilder
 * @coversDefaultClass \MediaWiki\User\UserSelectQueryBuilder
 * @package MediaWiki\Tests\User
 */
class UserSelectQueryBuilderTest extends ActorStoreTestBase {
	public function provideFetchUserIdentitiesByNamePrefix() {
		yield 'nothing found' => [
			'z_z_Z_Z_z_Z_z_z', // $prefix
			[ 'limit' => 100 ], // $options
			[], // $expected
		];
		yield 'default parameters' => [
			'Test', // $prefix
			[ 'limit' => 100 ], // $options
			[
				new UserIdentityValue( 24, 'TestUser', 42 ),
				new UserIdentityValue( 25, 'TestUser1', 44 ),
			], // $expected
		];
		yield 'limited' => [
			'Test', // $prefix
			[ 'limit' => 1 ], // $options
			[
				new UserIdentityValue( 24, 'TestUser', 42 ),
			], // $expected
		];
		yield 'sorted' => [
			'Test', // $prefix
			[
				'sort' => UserSelectQueryBuilder::SORT_DESC,
				'limit' => 100,
			], // $options
			[
				new UserIdentityValue( 25, 'TestUser1', 44 ),
				new UserIdentityValue( 24, 'TestUser', 42 ),
			], // $expected
		];
	}

	/**
	 * @dataProvider provideFetchUserIdentitiesByNamePrefix
	 */
	public function testFetchUserIdentitiesByNamePrefix( string $prefix, array $options, array $expected ) {
		$queryBuilder = $this->getStore()
			->newSelectQueryBuilder()
			->limit( $options['limit'] )
			->userNamePrefix( $prefix )
			->caller( __METHOD__ )
			->orderByName( $options['sort'] ?? SelectQueryBuilder::SORT_ASC );
		$actors = iterator_to_array( $queryBuilder->fetchUserIdentities() );
		$this->assertCount( count( $expected ), $actors );
		foreach ( $expected as $idx => $expectedActor ) {
			$this->assertSameActors( $expectedActor, $actors[$idx] );
		}
	}

	public function provideFetchUserIdentitiesByUserIds() {
		yield 'default parameters' => [
			[ 24, 25 ], // ids
			[], // $options
			[
				new UserIdentityValue( 24, 'TestUser', 42 ),
				new UserIdentityValue( 25, 'TestUser1', 44 ),
			], // $expected
		];
		yield 'sorted' => [
			[ 24, 25 ], // ids
			[ 'sort' => UserSelectQueryBuilder::SORT_DESC ], // $options
			[
				new UserIdentityValue( 25, 'TestUser1', 44 ),
				new UserIdentityValue( 24, 'TestUser', 42 ),
			], // $expected
		];
	}

	/**
	 * @dataProvider provideFetchUserIdentitiesByUserIds
	 */
	public function testFetchUserIdentitiesByUserIds( array $ids, array $options, array $expected ) {
		$actors = iterator_to_array(
			$this->getStore()
				->newSelectQueryBuilder()
				->userIds( $ids )
				->caller( __METHOD__ )
				->orderByUserId( $options['sort'] ?? SelectQueryBuilder::SORT_ASC )
				->fetchUserIdentities()
		);
		$this->assertCount( count( $expected ), $actors );
		foreach ( $expected as $idx => $expectedActor ) {
			$this->assertSameActors( $expectedActor, $actors[$idx] );
		}
	}

	public function provideFetchUserIdentitiesByNames() {
		yield 'default parameters' => [
			[ 'TestUser', 'TestUser1' ], // $names
			[], // $options
			[
				new UserIdentityValue( 24, 'TestUser', 42 ),
				new UserIdentityValue( 25, 'TestUser1', 44 ),
			], // $expected
		];
		yield 'sorted' => [
			[ 'TestUser', 'TestUser1' ], // $names
			[ 'sort' => UserSelectQueryBuilder::SORT_DESC ], // $options
			[
				new UserIdentityValue( 25, 'TestUser1', 44 ),
				new UserIdentityValue( 24, 'TestUser', 42 ),
			], // $expected
		];
		yield 'with IPs' => [
			[ self::IP ], // $names
			[], // $options
			[
				new UserIdentityValue( 0, self::IP, 43 ),
			], // $expected
		];
		yield 'with IPs, normalization' => [
			[ strtolower( self::IP ), self::IP ], // $names
			[], // $options
			[
				new UserIdentityValue( 0, self::IP, 43 ),
			], // $expected
		];
	}

	/**
	 * @dataProvider provideFetchUserIdentitiesByNames
	 */
	public function testFetchUserIdentitiesByNames( array $names, array $options, array $expected ) {
		$actors = iterator_to_array(
			$this->getStore()
				->newSelectQueryBuilder()
				->userNames( $names )
				->caller( __METHOD__ )
				->orderByUserId( $options['sort'] ?? SelectQueryBuilder::SORT_ASC )
				->fetchUserIdentities()
		);
		$this->assertCount( count( $expected ), $actors );
		foreach ( $expected as $idx => $expectedActor ) {
			$this->assertSameActors( $expectedActor, $actors[$idx] );
		}
	}

	/**
	 * @covers ::fetchUserIdentity
	 */
	public function testFetchUserIdentity() {
		$this->assertSameActors(
			new UserIdentityValue( 24, 'TestUser', 42 ),
			$this->getStore()
				->newSelectQueryBuilder()
				->userIds( 24 )
				->fetchUserIdentity()
		);
	}

	/**
	 * @covers ::fetchUserNames
	 */
	public function testFetchUserNames() {
		$this->assertArrayEquals(
			[ 'TestUser', 'TestUser1' ],
			$this->getStore()
				->newSelectQueryBuilder()
				->conds( [ 'actor_id' => [ 42, 44 ] ] )
				->fetchUserNames()
		);
	}

	/**
	 * @covers ::registered
	 */
	public function testRegistered() {
		$actors = iterator_to_array(
			$this->getStore()
				->newSelectQueryBuilder()
				->conds( [ 'actor_id' => [ 42, 43 ] ] )
				->registered()
				->fetchUserIdentities()
		);
		$this->assertCount( 1, $actors );
		$this->assertSameActors(
			new UserIdentityValue( 24, 'TestUser', 42 ),
			$actors[0]
		);
	}

	/**
	 * @covers ::anon
	 */
	public function testAnon() {
		$actors = iterator_to_array(
			$this->getStore()
				->newSelectQueryBuilder()
				->limit( 100 )
				->userNamePrefix( '' )
				->anon()
				->fetchUserIdentities()
		);
		$this->assertCount( 1, $actors );
		$this->assertSameActors(
			new UserIdentityValue( 0, self::IP, 43 ),
			$actors[0]
		);
	}
}
