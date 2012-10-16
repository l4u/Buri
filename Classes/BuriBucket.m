//
//  BuriBucket.cpp
//  LevelDB
//
//  Created by Gideon de Kok on 10/10/12.
//  Copyright (c) 2012 Pave Labs. All rights reserved.
//

#import "BuriBucket.h"
#import "BuriSerialization.h"
#import "BuriIndex.h"

@implementation BuriBucket

@synthesize buri		= _buri;
@synthesize usedClass	= _usedClass;

- (id)initWithDB:(Buri *)aDb andObjectClass:(Class)aClass
{
	self = [super init];

	if (self) {
		_buri		= aDb;
		_name		= NSStringFromClass(aClass);
		_usedClass	= aClass;
		[self initBucketPointer];
	}

	return self;
}

#pragma mark -
#pragma mark Prefix generators

- (NSString *)prefixKey:(NSString *)origKey
{
	return [NSString stringWithFormat:@"2i_%@::%@", _name, origKey];
}

- (NSString *)prefixBinaryIndexKey:(NSString *)origKey
{
	return [NSString stringWithFormat:@"2i_%@_bin::%@", _name, origKey];
}

- (NSString *)prefixIntegerIndexKey:(NSString *)origKey
{
	return [NSString stringWithFormat:@"2i_%@_int::%@", _name, origKey];
}

- (NSString *)removePrefixFromKey:(NSString *)prefixedKey
{
	int slicePosition = [prefixedKey rangeOfString:[self bucketPointerKey]].length;

	return [prefixedKey substringFromIndex:slicePosition];
}

#pragma mark -
#pragma mark Index key generators

- (NSString *)indexKeyForBinaryIndex:(BuriBinaryIndex *)index writeObject:(BuriWriteObject *)wo
{
	return [self prefixBinaryIndexKey:[NSString stringWithFormat:@"%@->%@->%@", [index key], [index value], [wo key]]];
}

- (NSString *)indexKeyForIntegerIndex:(BuriIntegerIndex *)index writeObject:(BuriWriteObject *)wo
{
	return [self prefixIntegerIndexKey:[NSString stringWithFormat:@"%@->%@->%@", [index key], [index value], [wo key]]];
}

#pragma mark -
#pragma mark Bucket pointers

- (NSString *)bucketPointerKey
{
	return [self prefixKey:@""];
}

- (NSString *)exactBinaryIndexPointerForIndexKey:(NSString *)key value:(NSString *)value
{
    return [self prefixBinaryIndexKey:[NSString stringWithFormat:@"%@->%@", key, value]];
}

- (NSString *)exactIntegerIndexPointerForIndexKey:(NSString *)key value:(NSNumber *)value
{
    return [self prefixIntegerIndexKey:[NSString stringWithFormat:@"%@->%@", key, value]];
}

- (void)initBucketPointer
{
	NSString *value = [_buri getObject:[self bucketPointerKey]];

	if (!value) {
		[_buri putObject:@"*" forKey:[self bucketPointerKey]];
	}
}

- (void)initExactBinaryIndexPointerForIndexKey:(NSString *)key value:(NSString *)value
{                  
    NSString *idxValue = [_buri getObject:[self exactBinaryIndexPointerForIndexKey:key value:value]];
    
	if (!idxValue) {
		[_buri putObject:@"*" forKey:[self exactBinaryIndexPointerForIndexKey:key value:value]];
	}
}

- (void)initExactIntegerIndexPointerForIndexKey:(NSString *)key value:(NSNumber *)value
{
    NSString *idxValue = [_buri getObject:[self exactIntegerIndexPointerForIndexKey:key value:value]];
    
	if (!idxValue) {
		[_buri putObject:@"*" forKey:[self exactIntegerIndexPointerForIndexKey:key value:value]];
	}
}


#pragma mark -
#pragma mark Fetch methods

- (id)fetchObjectForKey:(NSString *)key
{
	BuriWriteObject *wo = [_buri getObject:[self prefixKey:key]];

	return [wo storedObject];
}

- (NSArray *)fetchKeysForBinaryIndex:(NSString *)indexField value:(NSString *)indexValue
{
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    NSString *indexPointer = [self exactBinaryIndexPointerForIndexKey:indexField value:indexValue];
    
	[_buri seekToKey:indexPointer andIterate:^BOOL (NSString * key, id value) {
        if ([key rangeOfString:indexPointer].location != 0)
            return NO;
        
        if (value)
            [keys addObject:value];
        return YES;
    }];
    
	// Remove pointer
    if ([keys count] > 0) {
        [keys removeObjectAtIndex:0];
    }
    
	return keys;
}

- (NSArray *)fetchObjectsForBinaryIndex:(NSString *)indexField value:(NSString *)value
{
    NSArray *keys = [self fetchKeysForBinaryIndex:indexField value:value];
    NSMutableArray *objects = [NSMutableArray array];
    for (NSString *key in keys) {
        id value = [_buri getObject:[self prefixKey:key]];
        if ([value isMemberOfClass:[BuriWriteObject class]]) {
            [objects addObject:[(BuriWriteObject *) value storedObject]];
        }
    }
    
    return objects;
}

- (NSArray *)fetchKeysForIntegerIndex:(NSString *)indexField value:(NSNumber *)indexValue
{
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    NSString *indexPointer = [self exactIntegerIndexPointerForIndexKey:indexField value:indexValue];
    
	[_buri seekToKey:indexPointer andIterate:^BOOL (NSString * key, id value) {
        if ([key rangeOfString:indexPointer].location != 0)
            return NO;
        
        if (value)
            [keys addObject:value];
        return YES;
    }];
    
	// Remove pointer
    if ([keys count] > 0) {
        [keys removeObjectAtIndex:0];
    }
    
	return keys;
}

- (NSArray *)fetchObjectsForIntegerIndex:(NSString *)indexField value:(NSNumber *)value
{
    NSArray *keys = [self fetchKeysForIntegerIndex:indexField value:value];
    NSMutableArray *objects = [NSMutableArray array];
    for (NSString *key in keys) {
        id value = [_buri getObject:[self prefixKey:key]];
        if ([value isMemberOfClass:[BuriWriteObject class]]) {
            [objects addObject:[(BuriWriteObject *) value storedObject]];
        }
    }
    
    return objects;
}

- (NSArray *)allKeys
{
	NSMutableArray *keys = [[NSMutableArray alloc] init];

	[_buri seekToKey:[self bucketPointerKey] andIterateKeys:^BOOL (NSString * key) {
			if ([key rangeOfString:[self bucketPointerKey]].location != 0)
				return NO;

			[keys addObject:[self removePrefixFromKey:key]];
			return YES;
		}];

	// Remove pointer
    if ([keys count] > 0) {
        [keys removeObjectAtIndex:0];
    }
    
	return keys;
}

- (NSArray *)allObjects
{
	NSMutableArray *objects = [[NSMutableArray alloc] init];

	[_buri seekToKey:[self bucketPointerKey] andIterate:^BOOL (NSString * key, id value) {
			if ([key rangeOfString:[self bucketPointerKey]].location != 0)
				return NO;

			if ([value isMemberOfClass:[BuriWriteObject class]]) {
				[objects addObject:[(BuriWriteObject *) value storedObject]];
			}

			return YES;
		}];

	return objects;
}

#pragma mark -
#pragma mark Store methods

- (void)storeObject:(NSObject <BuriSupport> *)object
{
	if ([object class] != _usedClass) {
		[NSException raise:@"Storing different object type" format:@"the object type you are trying to store, should be of the %@ class", NSStringFromClass(_usedClass)];
	}

	BuriWriteObject *wo = [[BuriWriteObject alloc] initWithBuriObject:object];
    
    [self storeBinaryIndexesForWriteObject:wo];
    [self storeIntegerIndexesForWriteObject:wo];
	
    [_buri putObject:wo forKey:[self prefixKey:[wo key]]];
}

- (void)storeBinaryIndexesForWriteObject:(BuriWriteObject *)wo
{
	NSArray *binaryIndexes = [wo binaryIndexes];

	for (BuriBinaryIndex *index in binaryIndexes) {
        [self initExactBinaryIndexPointerForIndexKey:[index key] value:[index value]];
		NSString *indexKey = [self indexKeyForBinaryIndex:index writeObject:wo];
		[_buri putObject:[wo key] forKey:indexKey];
	}
}

- (void)storeIntegerIndexesForWriteObject:(BuriWriteObject *)wo
{
	NSArray *integerIndexes = [wo integerIndexes];

	for (BuriIntegerIndex *index in integerIndexes) {
        [self initExactIntegerIndexPointerForIndexKey:[index key] value:[index value]];
		NSString *indexKey = [self indexKeyForIntegerIndex:index writeObject:wo];
		[_buri putObject:[wo key] forKey:indexKey];
	}
}

#pragma mark -
#pragma mark Delete methods

- (void)deleteObjectForKey:(NSString *)key
{
	BuriWriteObject *wo = [_buri getObject:[self prefixKey:key]];

	if (wo) {
		[self deleteWriteObject:wo];
	}
}

- (void)deleteObject:(NSObject <BuriSupport> *)object
{
	if ([object class] != _usedClass) {
		[NSException raise:@"Storing different object type" format:@"the object type you are trying to store, should be of the %@ class", NSStringFromClass(_usedClass)];
	}

	BuriWriteObject *wo = [[BuriWriteObject alloc] initWithBuriObject:object];
	[self deleteWriteObject:wo];
}

- (void)deleteWriteObject:(BuriWriteObject *)wo
{
	[self deleteBinaryIndexesForWriteObject:wo];
	[self deleteIntegerIndexesForWriteObject:wo];
	[_buri deleteObject:[wo key]];
}

- (void)deleteBinaryIndexesForWriteObject:(BuriWriteObject *)wo
{
	NSArray *binaryIndexes = [wo binaryIndexes];

	for (BuriBinaryIndex *index in binaryIndexes) {
		NSString *indexKey = [self indexKeyForBinaryIndex:index writeObject:wo];
		[_buri deleteObject:indexKey];
	}
}

- (void)deleteIntegerIndexesForWriteObject:(BuriWriteObject *)wo
{
	NSArray *integerIndexes = [wo integerIndexes];

	for (BuriIntegerIndex *index in integerIndexes) {
		NSString *indexKey = [self indexKeyForIntegerIndex:index writeObject:wo];
		[_buri deleteObject:indexKey];
	}
}

@end